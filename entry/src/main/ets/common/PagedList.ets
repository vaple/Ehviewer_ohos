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

/** 分页数据源：`setItems` 整体替换并通知；`hasMore` 由调用方按"末批是否满页"维护。 */
export class PagedDataSource<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];
  private hasMore: boolean = true;
  private loading: () => boolean;
  private onNeedMore: () => void;

  constructor(onNeedMore: () => void, loading: () => boolean) {
    this.onNeedMore = onNeedMore;
    this.loading = loading;
  }

  setItems(items: T[], hasMore: boolean): void {
    this.items = items;
    this.hasMore = hasMore;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    if (shouldFetchMore(this.items.length, index, this.hasMore, this.loading())) {
      this.onNeedMore();
    }
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
