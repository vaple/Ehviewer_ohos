/**
 * 分页懒加载数据源（`LazyForEach + IDataSource` 官方范式；后端分页列表用）。
 * 触发点在 `getData`：框架按可视区 + `cachedCount` 预取后续序号，
 * 当请求的序号进入尾部窗口即回调 `onNeedMore`（25 条滑到 ~20 条即发下一页）。
 * 加载互斥与"还有更多"由调用方状态机保证（`isLoading` / `hasMore` 回调）。
 */

/** 尾部预取窗口（索引数；25 条/页 → 滑到 ~20 条触发）。 */
export const PREFETCH_TAIL: number = 6;

/** 是否该预取下一页（纯函数，行为即断言）。 */
export function shouldFetchMore(loaded: number, requestedEnd: number,
  hasMore: boolean, loading: boolean): boolean {
  if (loading || !hasMore) {
    return false;
  }
  return requestedEnd >= loaded - PREFETCH_TAIL;
}

/**
 * 分页数据源：`setItems` 整体替换并通知；`hasMore` 由 `GalleryListFeed` 的出参决定。
 *
 * **`getData` 不触发加载**：它是读操作，副作用会让"渲染"变成"发请求"，历史上就是这样自激成无限翻页的
 * （`ui/AGENTS.md` #66）。预取由页面在滚动到尾部时显式调用（复用 `shouldFetchMore`）。
 */
export class PagedDataSource<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];
  private hasMore: boolean = true;
  private loading: () => boolean;

  constructor(loading: () => boolean) {
    this.loading = loading;
  }

  setItems(items: T[], hasMore: boolean): void {
    this.items = items;
    this.hasMore = hasMore;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /** 页面在滚动到底部时问一次：现在该不该再取一页。 */
  wantsMore(requestedEnd: number): boolean {
    return shouldFetchMore(this.items.length, requestedEnd, this.hasMore, this.loading());
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) {
      this.listeners.splice(at, 1);
    }
  }
}
