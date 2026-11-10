import { PreviewCell } from '../model/PreviewCell';
import { PreviewItem } from '../model/PreviewItem';

/**
 * 一个站点预览块（固定 20 页）的成品：格子（缩略图 URL + 裁剪矩形）与页 token。
 * `tokens` 按「绝对页号 - 1」索引，与 `reader/TokenChunks.merge` 的约定一致。
 */
export interface PreviewChunk {
  cells: PreviewCell[];
  tokens: string[];
}

/**
 * 预览块的唯一缓存：详情网格、跳页条带、阅读器共用。
 *
 * 为什么要有它：三处要的是**同一份资源**——`/g/<gid>/<token>/?p=<chunk>` 一块 20 页，
 * 块 HTML 同时给出 pToken 和精灵图 URL。没有它时详情页自己缓存、阅读器再为 token 拉一遍，
 * 同一块会发两条请求；有它之后阅读器读 token 的同时就把缩略图存好了。
 *
 * 同一时刻只缓存一个画廊（`gid` 变化整清）：阅读器总是从同 gid 的详情页/下载页进入。
 * 位图不在这里，继续走静态的 `PreviewSpriteCache`（带引用计数）。
 */
export class PreviewChunkStore {
  /** 失败块冷却：3s 内不再重发，避免一次网络抖动打成请求风暴。 */
  static readonly RETRY_MS: number = 3000;
  private static shared: PreviewChunkStore | undefined = undefined;

  static get instance(): PreviewChunkStore {
    if (PreviewChunkStore.shared === undefined) {
      PreviewChunkStore.shared = new PreviewChunkStore();
    }
    return PreviewChunkStore.shared;
  }

  private gid: number = 0;
  private chunks: Map<number, PreviewChunk> = new Map<number, PreviewChunk>();
  /** 同块 single-flight：在飞时后来者 await 同一份，不再发请求。 */
  private inflight: Map<number, Promise<PreviewChunk>> = new Map<number, Promise<PreviewChunk>>();
  private failedAt: Map<number, number> = new Map<number, number>();
  private now: () => number = () => Date.now();
  private retryMs: number = PreviewChunkStore.RETRY_MS;

  /** 时钟/冷却可注入：单测用假时钟验证「3s 内不重发、之后重试」。 */
  constructor(now?: () => number, retryMs?: number) {
    if (now !== undefined) {
      this.now = now;
    }
    if (retryMs !== undefined) {
      this.retryMs = retryMs;
    }
  }

  /** 换画廊 / 登录态变化时整清。 */
  reset(gid: number = 0): void {
    this.gid = gid;
    this.chunks.clear();
    this.inflight.clear();
    this.failedAt.clear();
  }

  /** 同步读缓存（阅读器拖动时先看这里，没有才去取）。 */
  peek(gid: number, chunk: number): PreviewChunk | undefined {
    return gid === this.gid ? this.chunks.get(chunk) : undefined;
  }

  /** 失败块是否还在冷却期（调用方发起前先问，避免每次滚动都打一条日志）。 */
  failedRecently(gid: number, chunk: number): boolean {
    if (gid !== this.gid) {
      return false;
    }
    const failed: number | undefined = this.failedAt.get(chunk);
    return failed !== undefined && this.now() - failed < this.retryMs;
  }

  /** 详情页首块 / 阅读器详情响应自带的预览直接入库；已有块不覆盖。空块不入库。 */
  seed(gid: number, chunk: number, items: PreviewItem[]): PreviewChunk {
    this.syncGid(gid);
    const existing: PreviewChunk | undefined = this.chunks.get(chunk);
    if (existing !== undefined) {
      return existing;
    }
    if (items.length === 0) {
      // 空块不钉住：可能是详情首块解析失败 / 限流页，留给 `ensure` 重试。
      return PreviewChunkStore.build(items);
    }
    const built: PreviewChunk = PreviewChunkStore.build(items);
    this.chunks.set(chunk, built);
    this.failedAt.delete(chunk);
    return built;
  }

  /**
   * 取一块：命中 → 返回；在飞 → 等同一份；失败 3s 冷却。
   * `fetch` 由调用方注入（详情页 / 阅读器各用自己的 `EhClient`，二者共用一个 RCP session）。
   */
  ensure(gid: number, chunk: number,
    fetch: () => Promise<PreviewItem[]>): Promise<PreviewChunk> {
    this.syncGid(gid);
    const cached: PreviewChunk | undefined = this.chunks.get(chunk);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const running: Promise<PreviewChunk> | undefined = this.inflight.get(chunk);
    if (running !== undefined) {
      return running;
    }
    if (this.failedRecently(gid, chunk)) {
      return Promise.reject(new Error('preview chunk cooling down'));
    }
    let task: Promise<PreviewChunk>;
    task = fetch().then((items: PreviewItem[]) => {
      if (this.inflight.get(chunk) === task) {
        this.inflight.delete(chunk);
      }
      if (this.gid !== gid) {
        // 中途换了画廊：旧响应不能写进新画廊的缓存。
        throw new Error('gallery changed');
      }
      if (items.length === 0) {
        // 空块不是「这块没有预览」：限流页（Sessions number reached limit）也没有 #gdt，
        // 会解析成空数组。阅读器的 pToken 也从这里取，钉住空块会让这 20 页永久读不出来。
        this.failedAt.set(chunk, this.now());
        throw new Error('empty preview chunk');
      }
      const built: PreviewChunk = PreviewChunkStore.build(items);
      this.chunks.set(chunk, built);
      this.failedAt.delete(chunk);
      return built;
    }, (e: object) => {
      if (this.inflight.get(chunk) === task) {
        this.inflight.delete(chunk);
      }
      if (this.gid === gid) {
        this.failedAt.set(chunk, this.now());
      }
      // ArkTS 只允许 throw Error（arkts-limited-throw）：原样是 Error 就保留，否则包一层。
      if (e instanceof Error) {
        throw e;
      }
      throw new Error(`${e}`);
    });
    this.inflight.set(chunk, task);
    return task;
  }

  /** 所有入口先对齐 gid：换画廊时整清（同一时刻只缓存一个画廊）。 */
  private syncGid(gid: number): void {
    if (gid !== this.gid) {
      this.reset(gid);
    }
  }

  private static build(items: PreviewItem[]): PreviewChunk {
    const cells: PreviewCell[] = [];
    const tokens: string[] = [];
    for (let i = 0; i < items.length; i++) {
      const it: PreviewItem = items[i];
      const cell: PreviewCell = new PreviewCell();
      cell.page = it.page;
      cell.url = it.imageUrl;
      cell.x = it.x;
      cell.y = it.y;
      cell.w = it.w;
      cell.h = it.h;
      cells.push(cell);
      tokens[it.page] = it.pToken;
    }
    return { cells: cells, tokens: tokens };
  }
}
