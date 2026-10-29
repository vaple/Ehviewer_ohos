/**
 * 阅读进度：每个 gid 记一页（**页码 0 起**，与 `ReaderMode` 的内部页码一致）。
 *
 * 连接方式（在 UI 组件里调用）：
 * ```
 * PersistenceV2.globalConnect({
 *   type: ReadingProgressStore, key: 'ReadingProgressStore',
 *   defaultCreator: () => new ReadingProgressStore()
 * })
 * ```
 * 上限 `MAX_ENTRIES`，LRU 用 `Map` 的插入序实现（命中 `delete`+`set` 移尾，超限删最早的 key）——
 * 不需要额外的时间戳字段，落盘体积也更小。
 */
@ObservedV2
export class ReadingProgressStore {
  /** LRU 上限：避免单 key 无限增长（同时控制落盘体积）。 */
  static readonly MAX_ENTRIES: number = 500;

  /** gid（字符串键）→ 页码。**只读**：写入必须走 `save()`/`clear()`，否则绕过 LRU 上限与落盘触发。 */
  @Trace pages: Map<string, number> = new Map<string, number>();

  /** 记录某 gid 看到的页码；命中即移到末尾。 */
  save(gid: number, page: number): void {
    // 落盘再读回来时 Map 的值可能是字符串（框架按 `Ma0003[["gid","57"]]` 编码），统一收敛成数字。
    const value: number = Math.trunc(Number(page));
    this.pages.delete(`${gid}`);
    this.pages.set(`${gid}`, Number.isFinite(value) ? value : 0);
    while (this.pages.size > ReadingProgressStore.MAX_ENTRIES) {
      this.pages.delete(oldestKey(this.pages));
    }
  }

  /** 无记录返回 `-1`；命中会刷新 LRU 顺序。 */
  load(gid: number): number {
    const page: number | undefined = this.pages.get(`${gid}`);
    if (page === undefined) {
      return -1;
    }
    const value: number = Math.trunc(Number(page));
    if (!Number.isFinite(value)) {
      this.pages.delete(`${gid}`);
      return -1;
    }
    this.save(gid, value);
    return value;
  }

  /** 只读当前值（不刷新 LRU、不写状态；渲染期专用，避免 @Trace 写入引发重渲染）。 */
  peek(gid: number): number {
    const page: number | undefined = this.pages.get(`${gid}`);
    if (page === undefined) {
      return -1;
    }
    const value: number = Math.trunc(Number(page));
    return Number.isFinite(value) ? value : -1;
  }

  size(): number {
    return this.pages.size;
  }
}

/** `Map` 里最早插入（最旧）的 key；不用迭代器 API，避开 ArkTS 类型摩擦。 */
function oldestKey(pages: Map<string, number>): string {
  let oldest: string = '';
  let found: boolean = false;
  pages.forEach((_page: number, key: string) => {
    if (!found) {
      oldest = key;
      found = true;
    }
  });
  return oldest;
}
