import { appTasks, OhosPluginId, OhosAppContext } from '@ohos/hvigor-ohos-plugin';
import { getNode, hvigor, HvigorNode } from '@ohos/hvigor';
import { execFileSync } from 'child_process';

/**
 * 内置标签翻译快照（`entry/src/main/resources/rawfile/tagdb.v1.tsv`）**不入库**：
 * 它是第三方词典数据（数万条标签与释义），入库会让 GitCode 等镜像仓把整份内容当源码扫描。
 * 改为构建期生成：脚本自己读本地快照的 `#source`，再对上游发一次条件请求（`If-None-Match`），
 * 内容没变时服务端回 304、几乎不传字节；变了才下 4.3 MB 重新生成。
 *
 * 代价（已与用户确认）：构建与门禁都需要联网，且 python 必须在 PATH 里。
 * 不要改成"缺失就跳过"——那会让构建悄悄产出没有内置翻译的包，而这正是本钩子要防的事。
 */
const TAGDB_SCRIPT = 'scripts/tagdb/build_tagdb.py';

function ensureTagdb(): void {
  const python = process.env.PYTHON ?? 'python';
  try {
    execFileSync(python, [TAGDB_SCRIPT, '--ensure'], {
      cwd: __dirname,
      stdio: 'inherit',
      timeout: 300_000
    });
  } catch (err) {
    throw new Error(
      `标签翻译快照生成失败（${python} ${TAGDB_SCRIPT} --ensure）：${(err as Error).message}\n` +
      '构建需要联网，且 python 必须在 PATH 里（可用 PYTHON 环境变量指定解释器）；详见 AGENTS.md §5。'
    );
  }
}

/**
 * versionCode 由 AppScope/app.json5 的 versionName 在**构建期**算出并注入，
 * versionName 是唯一真源；磁盘上 app.json5 的 versionCode 只作可读性参考，
 * 每次构建都会被这里覆盖（所以不用手工维护，也不会写回源文件）。
 *
 *   versionCode = major * 1_000_000 + minor * 10_000 + patch * 100
 *   1.0.0 -> 1000000 / 1.0.1 -> 1000100 / 1.2.3 -> 1020300
 */
const SEMVER = /^(\d+)\.(\d+)\.(\d+)$/;

function versionCodeOf(versionName: string): number {
  const matched = SEMVER.exec(versionName);
  if (!matched) {
    throw new Error(
      `versionName 必须是 x.y.z 形式，当前是 ${JSON.stringify(versionName)}（AppScope/app.json5）。` +
      ' versionCode 由它算出，构建不会猜版本。'
    );
  }
  const major = Number(matched[1]);
  const minor = Number(matched[2]);
  const patch = Number(matched[3]);
  if (minor > 99 || patch > 99) {
    throw new Error(`versionName 的 minor/patch 不能超过 99，当前是 ${versionName}（否则公式会串位）`);
  }
  return major * 1_000_000 + minor * 10_000 + patch * 100;
}

hvigor.nodesEvaluated(() => {
  // 快照要先于打包生成（rawfile 会被打进 HAP）；源码里没有任何文件 import 它。
  ensureTagdb();
  const node: HvigorNode = getNode(__filename);
  const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const appJson = appContext.getAppJsonOpt();
  const versionName = appJson.app.versionName;
  const versionCode = versionCodeOf(versionName);
  if (appJson.app.versionCode !== versionCode) {
    console.log(`[version] versionName ${versionName} -> versionCode ${appJson.app.versionCode} => ${versionCode}`);
    appJson.app.versionCode = versionCode;
    appContext.setAppJsonOpt(appJson);
  }
});

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
