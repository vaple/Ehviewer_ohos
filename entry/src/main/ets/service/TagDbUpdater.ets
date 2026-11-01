import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { Logger } from '../common/Logger';
import { HttpResponse } from '../network/HttpClient';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { TAGDB_FILE, TagDb, TagDbStatus } from '../tagdb/TagDb';
import { dbJsonToTsv } from '../tagdb/TagDbConvert';
import { parseTagDb } from '../tagdb/TagDbFormat';
import { CodedError, describeError } from '../tagdb/ErrorDescribe';

/**
 * 标签翻译的手动更新链路（spec §7）。
 *
 * 为什么直连 `RcpHttpClient` 而不是 `EhClient`：数据源是 GitHub raw，不是站点；`EhClient` 会给请求带上
 * 站点 Cookie / 站点错误映射，既没必要也会把登录态泄给第三方域名。
 *
 * 为什么中途失败要换成中文再抛：`updateTagDb` 是 UI 唯一的错误边界。JSON/格式错误里的行号、列数
 * 对用户没有信息量（"错误优先暴露"针对的是不静默成功，不是把堆栈糊到屏幕上），原始异常一律
 * `Logger.error` 记全，抛给页面的只留一句人话。现有快照全程不被触碰。
 */

/** 上游原始 JSON（GFDL / CC BY-NC-SA 3.0）；与 `tools/tagdb/build_tagdb.py` 同一个源。 */
export const TAGDB_SOURCE_URL: string =
  'https://raw.githubusercontent.com/EhTagTranslation/Database/release/db.text.json';

/** 4.3 MB 载荷 + 3 MB 文本转换，60s 覆盖慢网；再长说明链路已经坏了，不该让按钮一直转。 */
const UPDATE_TIMEOUT_MS: number = 60000;

/** `ENOSPC`：只有这个平台错误才值得对用户提「存储空间」，权限 / 重名 / IO 错误不背这个锅。 */
const NO_SPACE_CODE: number = 13900025;

export type TagUpdateOutcome = 'UPDATED' | 'UP_TO_DATE';

/**
 * 下载 → 转换 → 校验 → 原子写盘 → 重新加载。失败抛错，磁盘上的旧快照保持原样。
 *
 * `UP_TO_DATE` 是唯一"成功但没写盘"的结果（sha 相同）；其余成功路径都会写盘并重新加载。
 * 开关在下载/加载期间被关掉不算失败：文件已经落盘，下次开启时会自动读到它。
 */
export async function updateTagDb(ctx: common.Context): Promise<TagUpdateOutcome> {
  // 4 MB 下载期间用户完全可以关掉开关；记录进入时的状态，只为了日志能说清"关掉"还是"本来就是关的"。
  const enabledAtStart: boolean = TagDb.enabled();

  const client: RcpHttpClient = new RcpHttpClient();
  let body: string = '';
  try {
    const resp: HttpResponse = await client.get(TAGDB_SOURCE_URL, { timeoutMs: UPDATE_TIMEOUT_MS });
    body = resp.body;
  } catch (e) {
    Logger.error('TagDb', `update: download failed: ${describeError(e as Object)}`);
    throw new Error('下载失败，请检查网络后重试');
  }

  // 转换与校验放在同一步：两者都属于"这份响应不可用"，对用户是同一句话。
  // 校验必须在写盘**之前**：写坏的快照会被加载器删掉，还会让这次启动的翻译直接消失。
  let text: string = '';
  let sha: string = '';
  try {
    text = dbJsonToTsv(body);
    const parsed = parseTagDb(text);
    sha = parsed.meta.sha;
  } catch (e) {
    Logger.error('TagDb', `update: convert/validate failed: ${describeError(e as Object)}`);
    throw new Error('下载的数据格式不对（上游可能改版了），已保留原有翻译');
  }

  const current: string | undefined = TagDb.status()?.sha;
  if (current !== undefined && current === sha) {
    Logger.info('TagDb', `update: up to date (${sha})`);
    return 'UP_TO_DATE';
  }

  try {
    writeSnapshot(ctx, text);
  } catch (e) {
    Logger.error('TagDb', `update: write failed: ${describeError(e as Object)}`);
    if ((e as CodedError).code === NO_SPACE_CODE) {
      throw new Error('存储空间不足，请清理后重试');
    }
    throw new Error('保存失败，请重试');
  }

  // 写盘后开关已经是关的：数据保留在磁盘上，`reload` 只会 `dropData()` 并 resolve。
  // 这不是失败（文件写成功了），按成功返回，状态行会显示「已关闭」。
  if (!TagDb.enabled()) {
    Logger.info('TagDb', `update: wrote ${sha} while translations are off ` +
      `(enabled at start: ${enabledAtStart}); will load on next enable`);
    return 'UPDATED';
  }

  try {
    await TagDb.reload(ctx);
  } catch (e) {
    Logger.error('TagDb', `update: reload failed: ${describeError(e as Object)}`);
    throw new Error('更新后加载失败，请重试');
  }
  // `reload` 在"没有可用候选"时只记 info 并 resolve（旧数据保留）。文件已经写进去了，但翻译没生效，
  // 这时候报成功就是假成功——必须按失败上报，让用户看到状态行没变成"已更新"。
  // 例外：开关恰好在 reload 期间被关掉（dropData 后 resolve），写盘本身是成功的，不能报失败。
  if (!TagDb.isReady()) {
    if (!TagDb.enabled()) {
      Logger.info('TagDb', `update: wrote ${sha}, switch turned off during reload; will load on next enable`);
      return 'UPDATED';
    }
    Logger.error('TagDb', `update: reload resolved without data (sha ${sha})`);
    throw new Error('更新后未能加载，请重试');
  }
  // 光"有数据"不够：加载规则按 `builtAt` 字典序取较新的那份，设备时钟明显偏慢时刚写的新快照会输给内置
  // 快照，状态行仍旧显示旧数据，而我们会报"已更新"。用实际生效的 sha 做最后一道对账。
  const applied: TagDbStatus | undefined = TagDb.status();
  if (applied === undefined || applied.sha !== sha) {
    const shown: string = applied === undefined ? 'none' : `${applied.source}/${applied.sha}`;
    Logger.error('TagDb', `update: new snapshot not applied (expected ${sha}, got ${shown})`);
    throw new Error('更新后数据未生效，请检查设备时间后重试');
  }

  Logger.info('TagDb', `update: applied ${sha} (${applied.count} tags)`);
  return 'UPDATED';
}

/**
 * 先写 `<name>.tmp`，再 `rename` 覆盖正式文件；**任何失败都清掉临时文件**。
 *
 * 为什么不直接写正式文件：写到一半被杀进程（或被系统回收）会留下半份快照，冷启动解析失败时
 * 加载器会把它删掉——用户看到的是"更新完成但翻译没了"。临时文件与目标同目录（同一文件系统），
 * `rename` 是原子替换：要么旧文件完整，要么新文件完整，不存在中间态。
 *
 * 为什么失败要删 `.tmp`：缓存清理只扫 cache 目录，`filesDir` 里的半份 3 MB 临时文件永远没人收；
 * 下一次更新虽然会 TRUNC 覆盖它，但失败后一直不更新就会永久占着空间。
 */
function writeSnapshot(ctx: common.Context, text: string): void {
  const target: string = `${ctx.filesDir}/${TAGDB_FILE}`;
  const tmp: string = `${target}.tmp`;
  try {
    writeTmp(tmp, text);
    fs.renameSync(tmp, target);
  } catch (e) {
    // 保留原始错误（unlink 自己失败只记日志，不能顶掉它）。ArkTS 只允许 throw Error 类型，
    // 所以先按 Error 取回同一个运行时对象（`code` 等字段不会被拷掉）。
    const err: Error = e as Error;
    removeTmpQuietly(tmp, err);
    throw err;
  }
}

/**
 * 写临时文件并校验字节数：`writeSync` 的返回值被忽略时，短写会静默产出一份被截断的 3 MB 文件，
 * 而它仍然能通过 `parseTagDb`（后半段没了但前缀合法）。
 *
 * `closeSync` 放在 `finally` 里，但**不能让它顶掉写失败的原因**：写抛错时 close 再抛，
 * 用户/日志看到的会是 close 的错，真正的磁盘错误反而丢了。
 */
function writeTmp(tmp: string, text: string): void {
  const expected: number = buffer.byteLength(text, 'utf-8');
  const file = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
  let primary: Object | undefined = undefined;
  try {
    const written: number = fs.writeSync(file.fd, text);
    if (written !== expected) {
      const shortErr: Error = new Error(`tagdb write: 短写 ${written}/${expected} 字节`);
      primary = shortErr;
      throw shortErr;
    }
  } catch (e) {
    const err: Error = e as Error;
    primary = err;
    throw err;
  } finally {
    try {
      fs.closeSync(file);
    } catch (closeErr) {
      const cerr: Error = closeErr as Error;
      if (primary === undefined) {
        throw cerr;
      }
      Logger.error('TagDb', `update: close tmp failed: ${describeError(cerr)}`);
    }
  }
}

/** 删临时文件；不存在（open 就失败了）不算错，删不掉也只在日志里记，不覆盖原始失败原因。 */
function removeTmpQuietly(path: string, primary: Object): void {
  try {
    if (!fs.accessSync(path)) {
      return;
    }
    fs.unlinkSync(path);
    Logger.info('TagDb', 'update: removed leftover tmp file');
  } catch (unlinkErr) {
    Logger.error('TagDb', `update: remove tmp failed: ${describeError(unlinkErr as Object)} ` +
      `(after: ${describeError(primary)})`);
  }
}
