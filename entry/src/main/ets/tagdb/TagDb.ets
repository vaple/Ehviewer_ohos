import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { resourceManager } from '@kit.LocalizationKit';
import { Logger } from '../common/Logger';
import { TagSettings, watchTagEnabled } from '../state/TagSettings';
import { TagCandidate } from './TagCandidate';
import { describeError } from './ErrorDescribe';
import {
  introOf, parseTagDb, peekBuiltAt, peekFormat, searchTags, TAGDB_FORMAT, TagDbData, translateNsOf, translateTagOf
} from './TagDbFormat';

/**
 * 标签翻译快照的运行期单例：加载（按生成时间取沙箱或内置）/ 状态 / 重绘信号 / 查询入口。
 *
 * 数据本身与解析规则全在 `TagDbFormat`（纯函数），这里只负责「从哪来、什么时候算就绪、开关怎么影响结果」。
 * 为什么要有独立的重绘信号 `tagDbRev`：译文不是 `@Param`，加载完成或切开关时只该重画 chip，
 * 不能重建详情页的 `Repeat` 预览图。查询函数首行读一次 `rev`，UI 节点在执行期间读到它就自动建立依赖。
 */

/** 沙箱副本与内置 rawfile 同名：更新流程写的就是这个名字，加载器不需要第二套常量。 */
export const TAGDB_FILE: string = 'tagdb.v1.tsv';

/**
 * 读内置快照头部用的字节数。
 * 头部固定两行：`#tagdb\t1\n`（9 B）+ `#source\t<40 位 sha>\t<20 位时间>\n`（70 B）≈ 80 B，取 256 留三倍余量。
 * 这是**上限**不是目标：解析仍按行做，第二个换行没出现在窗口内就当作头部不可用。
 */
const BUNDLED_HEAD_BYTES: number = 256;

/** `@Trace rev` 是唯一的重绘信号：数据装载、开关切换都会 +1。 */
@ObservedV2
export class TagDbRev {
  @Trace rev: number = 0;
}

export const tagDbRev: TagDbRev = new TagDbRev();

/** `bundled` = 安装包内置快照；`updated` = 沙箱里用户手动更新过的那份。 */
export type TagDbSource = 'bundled' | 'updated';

export interface TagDbStatus {
  source: TagDbSource;
  sha: string;
  /** 生成时间 ISO8601 UTC（设置页显示用）。 */
  builtAt: string;
  /** `#tags` 条目数（不含 `#rows` 命名空间索引）。 */
  count: number;
}

/** 选片结果：`data` 是胜出的那份，`source` 只用于设置页的状态文案。 */
export interface TagDbPick {
  data: TagDbData;
  source: TagDbSource;
}

/**
 * 两份快照都有效时取 `builtAt` 较新的那份（spec §7）。
 *
 * 为什么不能"沙箱能解析就用沙箱"：App 升级会带来更新的内置快照，而用户沙箱里可能躺着上一版
 * （或很久以前手动更新过）的文件——只认沙箱会把翻译永久钉在旧数据上，状态行还会把旧日期说成「已更新」。
 *
 * 比较用字符串字典序：格式规定 `builtAt` 是定长 ISO8601 UTC（见 `TagDbConvert`），字典序即时间序。
 * 相等时取沙箱：内容同源（`sha` 相同）时没必要换，也避免为一份更旧的内置数据重画界面。
 */
export function pickNewerSnapshot(sandbox: TagDbData | undefined,
  bundled: TagDbData | undefined): TagDbPick | undefined {
  if (sandbox === undefined) {
    return bundled === undefined ? undefined : { data: bundled, source: 'bundled' };
  }
  if (bundled === undefined || sandbox.meta.builtAt >= bundled.meta.builtAt) {
    return { data: sandbox, source: 'updated' };
  }
  return { data: bundled, source: 'bundled' };
}

export class TagDb {
  /** 未加载或开关关闭时必须是 `undefined`——关闭要真的释放 ≈8 MB，不能只靠查询时跳过。 */
  private static data: TagDbData | undefined = undefined;
  private static source: TagDbSource = 'bundled';
  /** 进行中的加载（single-flight）：`onAppear` 与更新后的 `reload` 撞在一起时只读一遍 3 MB。 */
  private static loading: Promise<void> | undefined = undefined;
  /** 开关来源；`undefined` = 还没绑定（单测/冷启动早期），按「开启」处理。 */
  private static settings: TagSettings | undefined = undefined;
  /** 最近一次拿到的 Context：开关重新打开时要自己回读文件，不依赖页面再传一次。 */
  private static hostContext: common.Context | undefined = undefined;
  /**
   * 最近一次加载是否失败。`data === undefined` + 开关开着时界面必须能区分「还在加载」与「已经失败」，
   * 否则状态行永远停在「加载中…」，用户不知道要看诊断日志。
   */
  private static loadFailed: boolean = false;

  // ---- 开关 ----

  /**
   * 绑定开关来源。`AppShell.onAppear` 在 `ensureLoaded` 之前调用。
   *
   * 绑定后由 `TagSettings.enabled` 的 setter 推送变化（见 `state/TagSettings.ets` 里为什么不用 @Monitor）：
   * 关闭 → 立刻释放数据 + `rev++`，打开 → 用缓存的 Context 重新载入。页面只改开关值，不需要自己调 `reload`。
   */
  static bindSettings(settings: TagSettings): void {
    TagDb.settings = settings;
    watchTagEnabled((enabled: boolean): void => {
      TagDb.onEnabledChanged(enabled);
    });
  }

  private static onEnabledChanged(enabled: boolean): void {
    if (!enabled) {
      TagDb.dropData();
      return;
    }
    const ctx: common.Context | undefined = TagDb.hostContext;
    if (ctx === undefined) {
      // 还没装载过（AppShell 尚未 ensureLoaded）：没有数据要重建，等它来；这里读盘没有意义。
      return;
    }
    // 监听回调不能 await；失败只记日志（数据为空时界面就是原文，不会假装成功），但要置 `loadFailed`
    // 让设置页能把「加载中…」换成失败提示。
    TagDb.reload(ctx).catch((e: Error): void => {
      Logger.error('TagDb', `reload after enable failed: ${describeError(e)}`);
      TagDb.markFailed();
    });
  }

  /**
   * 开关当前是否开启（未绑定设置时按开启处理）。公开是因为更新流程要判断「下载期间用户关掉了开关」：
   * 那种情况写盘已经成功，但 `reload` 会释放数据，不能按失败上报。
   */
  static enabled(): boolean {
    const settings: TagSettings | undefined = TagDb.settings;
    return settings === undefined || settings.enabled;
  }

  // ---- 加载 ----

  /**
   * 业务入口：确保数据可用。启动路径是 fire-and-forget，失败只记 error + 置 `loadFailed`、不置 ready。
   * 开关关闭时直接返回、**不读任何文件**。
   */
  static ensureLoaded(ctx: common.Context): Promise<void> {
    return TagDb.start(ctx, false).catch((e: Error): void => {
      // 调用方不 await：吞掉 rejection 只为了让宿主不冒未处理拒绝，错误本身已进日志 + 状态位。
      Logger.error('TagDb', `load failed: ${describeError(e)}`);
      TagDb.markFailed();
    });
  }

  /**
   * 重新读取磁盘（更新写盘后 / 开关重新打开后）。**失败会 reject**，调用方据此报错，
   * 不能像 `ensureLoaded` 那样吞掉——否则更新流程会在翻译根本没生效时显示成功。
   * 解析成功才 install，失败时旧数据原样保留（不会先清空再失败）。
   */
  static reload(ctx: common.Context): Promise<void> {
    // 先等正在进行的加载收尾（无论成败），保证这次读到的是刚落盘的文件。
    const active: Promise<void> | undefined = TagDb.loading;
    const settled: Promise<void> = active === undefined
      ? Promise.resolve()
      : active.then((): void => {
      }, (): void => {
      });
    return settled.then((): Promise<void> => TagDb.start(ctx, true));
  }

  /**
   * 核心加载：去重 + 已就绪短路；**失败原样 reject**（`ensureLoaded` 吞、`reload` 冒）。
   * `force` = 即使已有数据也重新读（更新/开关恢复用；已有数据时失败不丢旧数据）。
   */
  private static start(ctx: common.Context, force: boolean): Promise<void> {
    TagDb.hostContext = ctx;
    if (!TagDb.enabled()) {
      TagDb.dropData();
      return Promise.resolve();
    }
    if (!force && TagDb.data !== undefined) {
      return Promise.resolve();
    }
    const active: Promise<void> | undefined = TagDb.loading;
    if (active !== undefined) {
      return active;
    }
    const started: Promise<void> = TagDb.load(ctx);
    TagDb.loading = started;
    // 成功或失败都要摘掉记录，否则一次失败会让这个会话永远拿到同一个 rejected promise。
    started.then((): void => {
      TagDb.loading = undefined;
    }, (): void => {
      TagDb.loading = undefined;
    });
    return started;
  }

  /** 加载器与单测共用：写入数据并触发重绘。开关关闭时只记来源、不保留数据。 */
  static install(data: TagDbData, source: TagDbSource): void {
    TagDb.source = source;
    TagDb.data = TagDb.enabled() ? data : undefined;
    TagDb.loadFailed = false;
    tagDbRev.rev++;
  }

  /**
   * 最近一次加载是否失败（设置页据此把「加载中…」换成失败提示）。
   * 与其它查询入口一样首行读 `rev`：失败/成功都要让读到它的页面重算。
   */
  static hasFailed(): boolean {
    tagDbRev.rev;
    return TagDb.loadFailed;
  }

  /** 置失败位并 `rev++`：否则页面读 `status()` 时依赖的 `rev` 没变，会一直停在旧的「加载中…」。 */
  private static markFailed(): void {
    TagDb.loadFailed = true;
    tagDbRev.rev++;
  }

  static isReady(): boolean {
    // 与 `status()` 同理：只读 `isReady()` 的页面（设置页判断是否显示状态行）也要在装载/切开关后重算。
    tagDbRev.rev;
    return TagDb.data !== undefined;
  }

  static status(): TagDbStatus | undefined {
    // 与查询入口同理：只读 `status()` 的页面（设置页）也要在装载完成 / 切换开关后重算。
    tagDbRev.rev;
    const db: TagDbData | undefined = TagDb.data;
    if (db === undefined) {
      return undefined;
    }
    const status: TagDbStatus = {
      source: TagDb.source,
      sha: db.meta.sha,
      builtAt: db.meta.builtAt,
      count: db.keys.length
    };
    return status;
  }

  private static dropData(): void {
    const hadData: boolean = TagDb.data !== undefined;
    TagDb.data = undefined;
    // `loadFailed` 必须一起清掉：否则关→开时 `status()` 仍是 undefined，设置页会先显示上一轮的
    // 「加载失败」，直到这次加载结束；用户看到的是一次莫名其妙的报错。
    const wasFailed: boolean = TagDb.loadFailed;
    TagDb.loadFailed = false;
    if (hadData || wasFailed) {
      tagDbRev.rev++;
    }
  }

  /** 仅单测用：清空所有模块级状态（含开关订阅），让用例互不影响。 */
  static __resetForTest(): void {
    TagDb.data = undefined;
    TagDb.source = 'bundled';
    TagDb.loading = undefined;
    TagDb.settings = undefined;
    TagDb.hostContext = undefined;
    TagDb.loadFailed = false;
    watchTagEnabled(undefined);
  }

  private static async load(ctx: common.Context): Promise<void> {
    // 先让出一拍：下面 `getRawFileContentSync` + 3.1 MB `parseTagDb` 全是同步的，
    // 在 `onAppear` 那一帧里做完会拖住首帧；让首帧先画出来再干重活。
    await TagDb.yieldTick();
    // 沙箱那份只要不比内置旧就直接装：内置的生成时间从 rawfile 头部读（约 80 B，一次 fd 读），
    // 不必解析整份 3.1 MB。但「能解析」本身不是理由——App 升级后内置会比沙箱新（spec §7），
    // 那种情况必须读内置并让两份比一次新旧，否则翻译会被旧沙箱永久钉住。
    // 头部读不出来时 `bundledBuiltAt` 是 undefined，直接走完整比较（宁可多解析一次，也不猜时间戳）。
    const sandbox: TagDbData | undefined = await TagDb.readSandbox(ctx);
    const bundledBuiltAt: string | undefined = TagDb.readBundledBuiltAt(ctx);
    if (sandbox !== undefined && bundledBuiltAt !== undefined && sandbox.meta.builtAt >= bundledBuiltAt) {
      TagDb.install(sandbox, 'updated');
      Logger.info('TagDb', `loaded updated snapshot: ${sandbox.keys.length} tags, built ${sandbox.meta.builtAt}`);
      return;
    }
    const bundled: TagDbData | undefined = TagDb.readBundled(ctx);
    const pick: TagDbPick | undefined = pickNewerSnapshot(sandbox, bundled);
    if (pick === undefined) {
      // 两份都不可用（内置缺失 / 不是本格式）：不能当成"加载成功、只是没数据"，
      // 否则设置页永远停在「加载中…」，用户没有任何线索去看诊断日志。
      Logger.error('TagDb', 'no usable snapshot: bundled unusable and sandbox missing/invalid');
      TagDb.markFailed();
      return;
    }
    TagDb.install(pick.data, pick.source);
    Logger.info('TagDb',
      `loaded ${pick.source} snapshot: ${pick.data.keys.length} tags, built ${pick.data.meta.builtAt}`);
  }

  /**
   * 沙箱副本：不存在 = 没更新过（正常）；格式不是本版本 → 忽略、**不删**（等下次更新覆盖）；
   * 自称本格式却解析不了 → 删掉（否则每次冷启动都炸同一处）。
   */
  private static async readSandbox(ctx: common.Context): Promise<TagDbData | undefined> {
    let path: string = '';
    try {
      // `filesDir` 与存在性探测都可能抛（权限/沙箱未就绪）：只丢这一份候选，内置快照仍要能装。
      path = `${ctx.filesDir}/${TAGDB_FILE}`;
      if (!fs.accessSync(path)) {
        return undefined;
      }
    } catch (e) {
      Logger.error('TagDb', `sandbox probe failed: ${describeError(e as Object)}`);
      return undefined;
    }
    let text: string = '';
    try {
      text = await fs.readText(path);
    } catch (e) {
      // 读不到（句柄/权限）不等于文件坏了：保留文件，下次启动再试。
      Logger.error('TagDb', `read sandbox failed: ${describeError(e as Object)}`);
      return undefined;
    }
    const version: number | undefined = peekFormat(text);
    if (version !== TAGDB_FORMAT) {
      // 包括 `1.0` / `v2` 这种首行不成形的文件：无法证明是本格式，就不该删别人的数据。
      const shown: string = version === undefined ? 'unknown' : `${version}`;
      Logger.info('TagDb', `sandbox snapshot format ${shown} != ${TAGDB_FORMAT}, ignored`);
      return undefined;
    }
    try {
      return parseTagDb(text);
    } catch (e) {
      try {
        fs.unlinkSync(path);
        Logger.error('TagDb', `sandbox snapshot parse failed, deleted: ${describeError(e as Object)}`);
      } catch (delErr) {
        // 删不掉也得继续用内置快照；下次启动会再撞一次同一处，必须留下痕迹。
        Logger.error('TagDb',
          `sandbox snapshot parse failed: ${describeError(e as Object)}; delete failed: ${describeError(delErr as Object)}`);
      }
      return undefined;
    }
  }

  /**
   * 内置快照：版本不符按「别的格式」忽略（记 info）；自称本格式却读不出 / 解析不了属于构建事故，
   * 直接上抛（由 `ensureLoaded` / `reload` 的调用方处理）。
   */
  private static readBundled(ctx: common.Context): TagDbData | undefined {
    const bytes: Uint8Array = ctx.resourceManager.getRawFileContentSync(TAGDB_FILE);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    const text: string = decoder.decodeToString(bytes);
    const version: number | undefined = peekFormat(text);
    if (version !== TAGDB_FORMAT) {
      const shown: string = version === undefined ? 'unknown' : `${version}`;
      Logger.info('TagDb', `bundled snapshot format ${shown} != ${TAGDB_FORMAT}, ignored`);
      return undefined;
    }
    // 自称本格式却解析不了 = 构建事故：不兜底、直接抛。
    return parseTagDb(text);
  }

  /**
   * 只读内置快照的头部，取 `#source` 的生成时间（约 80 B）。
   *
   * 用 fd 读前 `BUNDLED_HEAD_BYTES` 字节：格式把头部固定成两行（版本 + `#source`），
   * 读满一份 3.1 MB 只为一行元信息不划算。取不到（设备/打包方式不支持 fd、文件缺失、
   * 头部不合规）返回 undefined，调用方退回「读整份 + 两份比较」——不猜时间戳。
   */
  private static readBundledBuiltAt(ctx: common.Context): string | undefined {
    let opened: boolean = false;
    try {
      const region: resourceManager.RawFileDescriptor = ctx.resourceManager.getRawFdSync(TAGDB_FILE);
      opened = true;
      const size: number = Math.min(BUNDLED_HEAD_BYTES, region.length);
      if (size <= 0) {
        return undefined;
      }
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      const read: number = fs.readSync(region.fd, buffer, { offset: region.offset, length: size });
      if (read <= 0) {
        return undefined;
      }
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return peekBuiltAt(decoder.decodeToString(new Uint8Array(buffer, 0, read)));
    } catch (e) {
      Logger.info('TagDb', `bundled head unreadable, falling back to full compare: ${describeError(e as Object)}`);
      return undefined;
    } finally {
      if (opened) {
        try {
          ctx.resourceManager.closeRawFdSync(TAGDB_FILE);
        } catch (e) {
          // 关不掉不影响已读到的内容；fd 会随进程退出释放。
          Logger.info('TagDb', `closeRawFd failed: ${describeError(e as Object)}`);
        }
      }
    }
  }

  /** 让出一拍事件循环（0 ms）：同步解析前先给首帧绘制机会。 */
  private static yieldTick(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 0);
    });
  }

  // ---- 查询 ----
  // 每个入口首行读一次 `tagDbRev.rev`：ArkUI V2 只把「执行期间真实读到的 @Trace 属性」记为依赖，
  // 所以这行是 UI 在装载完成 / 切开关后自动重算的依据，不是摆设。

  static translateTag(ns: string, tag: string): string {
    tagDbRev.rev;
    const db: TagDbData | undefined = TagDb.data;
    if (db === undefined || !TagDb.enabled()) {
      return tag;
    }
    return translateTagOf(db, ns, tag);
  }

  static translateNs(ns: string): string {
    tagDbRev.rev;
    const db: TagDbData | undefined = TagDb.data;
    if (db === undefined || !TagDb.enabled()) {
      return ns;
    }
    return translateNsOf(db, ns);
  }

  static intro(ns: string, tag: string): string {
    tagDbRev.rev;
    const db: TagDbData | undefined = TagDb.data;
    if (db === undefined || !TagDb.enabled()) {
      return '';
    }
    return introOf(db, ns, tag);
  }

  static search(kw: string, limit: number): TagCandidate[] {
    tagDbRev.rev;
    const db: TagDbData | undefined = TagDb.data;
    if (db === undefined || !TagDb.enabled()) {
      return [];
    }
    return searchTags(db, kw, limit);
  }
}

