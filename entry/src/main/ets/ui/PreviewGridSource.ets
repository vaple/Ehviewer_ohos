import { PreviewCell } from '../model/PreviewCell';

/** 预览网格的一行（3 格；最后一页不足一整行时短一行）。 */
export class PreviewRow {
  cells: PreviewCell[] = [];
}

/**
 * 详情页预览网格的 `LazyForEach` 数据源（一行 = 3 页）。
 *
 * 为什么固定总行数：网格挂在详情页的 `List` 上，行数必须从详情回来那一刻就等于
 * `ceil(pages / 3)`——
 * - 滚动范围稳定：不会「越滚越长」，也不会因为某块晚到把用户当前滚动位置顶走；
 * - 未取到的页先用「页码灰块」占位，取到一块就只改那几格的 `@Trace` 字段。
 *
 * 为什么不用 `onDataChange` 驱动格子：`LazyForEach` 已建好的 item 不会因它重跑 builder
 * （`ui/AGENTS.md` #65）；格子由 `PreviewGridCell` 直接读 `@Trace` 字段自己重绘。
 */
export class PreviewGridSource implements IDataSource {
  private rows: PreviewRow[] = [];
  private listeners: DataChangeListener[] = [];
  /** 列数（行 → 页换算的唯一真值；页面不要另存一份）。 */
  readonly columns: number;
  /** 代际：每次 `reset` +1，`LazyForEach` 的 key 带上它，换画廊时不会复用旧格子（旧图/旧 ready 态）。 */
  generation: number = 0;

  constructor(columns: number) {
    this.columns = columns;
  }

  /** 换画廊 / 详情回来：按总页数重建占位行，并让 `LazyForEach` 重新取数。 */
  reset(pages: number): void {
    const rows: PreviewRow[] = [];
    const count: number = pages > 0 ? Math.ceil(pages / this.columns) : 0;
    for (let r = 0; r < count; r++) {
      const row: PreviewRow = new PreviewRow();
      for (let c = 0; c < this.columns; c++) {
        const page: number = r * this.columns + c;
        if (page >= pages) {
          break;
        }
        const cell: PreviewCell = new PreviewCell();
        cell.page = page;
        row.cells.push(cell);
      }
      rows.push(row);
    }
    this.rows = rows;
    this.generation += 1;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): PreviewRow {
    return this.rows[index];
  }

  /**
   * 把一块（20 页）预览项写进对应页的格子。
   * 页码由行位置决定，不覆盖（块响应的页码只用来定位）；只挡「页码越界 / 该行没有这一格」，
   * **换画廊的旧响应不靠这里**——由调用方 `fetchChunkCells` 的 gid 校验兜底。
   */
  apply(cells: PreviewCell[]): void {
    const totalPages: number = this.rows.length * this.columns;
    for (let i = 0; i < cells.length; i++) {
      const page: number = cells[i].page;
      if (page < 0 || page >= totalPages) {
        continue;
      }
      const row: PreviewRow = this.rows[Math.floor(page / this.columns)];
      const target: PreviewCell | undefined = row.cells[page % this.columns];
      if (target === undefined || target.page !== page) {
        continue;
      }
      target.url = cells[i].url;
      target.x = cells[i].x;
      target.y = cells[i].y;
      target.w = cells[i].w;
      target.h = cells[i].h;
    }
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
