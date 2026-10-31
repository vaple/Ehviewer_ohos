/**
 * 页 token（pToken）的分块取用。
 *
 * 背景：E-Hentai 详情页只自带**前 20 页**的 pToken，更远的页要按 20 页一块再请求
 * （`/g/<gid>/<token>/?p=<chunk>`），一块的响应一次给出该块 20 个 token。
 *
 * 为什么不是"调用方各取各的"：阅读器预取会一次并发十几个 `loadPage`，它们常常落在同一个
 * chunk。原先的短路条件是「`tokens[page]` 是否已有值」，而值要等请求**返回后才填**，
 * 于是同一毫秒进入的 4 个调用者全部通过检查、各发一次同样的 18 KB 请求（真机日志实测 4 条
 * 完全相同的 `?p=1`，开始时刻相差 <10 ms）。
 *
 * 这里把「正在进行」也记下来（single-flight）：后到的人 await 同一份 promise，不再发请求。
 * 失败必须把记录摘掉，否则一次网络抖动会让这个 chunk 永远拿到 rejected promise。
 */
export class TokenChunks {
  private perChunk: number;
  private load: (chunk: number) => Promise<string[]>;
  /** 页号-1 → token。 */
  private tokens: Map<number, string> = new Map<number, string>();
  /** chunk → 进行中的请求。 */
  private pending: Map<number, Promise<string[]>> = new Map<number, Promise<string[]>>();

  constructor(load: (chunk: number) => Promise<string[]>, perChunk: number = 20) {
    this.load = load;
    this.perChunk = perChunk;
  }

  /** 图片页 HTML 自带「下一页」token，先塞进来可以省一次分块请求（顺序翻页用）。 */
  put(page: number, token: string): void {
    this.tokens.set(page, token);
  }

  /** 预置详情页首块自带的前若干页。 */
  seed(tokens: string[]): void {
    this.merge(tokens);
  }

  /** 取某页 token；缺失时按块补取（同 chunk 并发只发一次）。 */
  async ensure(page: number): Promise<string | undefined> {
    const known: string | undefined = this.tokens.get(page);
    if (known !== undefined) {
      return known;
    }
    const chunk: number = Math.floor(page / this.perChunk);
    let pending: Promise<string[]> | undefined = this.pending.get(chunk);
    if (pending === undefined) {
      const started: Promise<string[]> = this.load(chunk);
      this.pending.set(chunk, started);
      started.then((): void => {
        this.pending.delete(chunk);
      }, (): void => {
        this.pending.delete(chunk);
      });
      pending = started;
    }
    this.merge(await pending);
    return this.tokens.get(page);
  }

  /** 合并解析结果：索引即「绝对页号 - 1」（`GalleryDetailParser.parsePreviewTokens` 的约定）。 */
  private merge(fetched: string[]): void {
    for (let i = 0; i < fetched.length; i++) {
      const token: string | undefined = fetched[i];
      if (token !== undefined && token.length > 0 && this.tokens.get(i) === undefined) {
        this.tokens.set(i, token);
      }
    }
  }
}
