import { PreviewCell } from '../model/PreviewCell';

/**
 * 跳页条带的 `LazyForEach` 数据源：页数固定，每页先占位（`url` 空 → 灰块 + 页码）。
 *
 * 为什么固定页数：条带要能从头滑到尾，条目数必须从打开那一刻就等于总页数；
 * 若按「已取到的块」拼数组，滚动范围会随取块变化 → 用户滑到一半列表自己变长/变短。
 *
 * 为什么取到块还要显式 `onDataChange`：`PreviewCell` 的字段带 `@Trace`，条带格子靠 V2 观察自己刷新
 * （见 `ui/JumpStripCell`）；这里的通知是「已建行可能没被观察」的兜底，重复触发只会重建一次，不会出错。
 */
export class PreviewStripSource implements IDataSource {
  private cells: PreviewCell[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(pages: number) {
    for (let page = 0; page < pages; page++) {
      const cell: PreviewCell = new PreviewCell();
      cell.page = page;
      this.cells.push(cell);
    }
  }

  totalCount(): number {
    return this.cells.length;
  }

  getData(index: number): PreviewCell {
    return this.cells[index];
  }

  /** 按 `cell.page` 落位并只通知该行；越界（换画廊后的旧响应）直接忽略。 */
  setCell(cell: PreviewCell): void {
    const page: number = cell.page;
    if (page < 0 || page >= this.cells.length) {
      return;
    }
    const target: PreviewCell = this.cells[page];
    target.url = cell.url;
    target.x = cell.x;
    target.y = cell.y;
    target.w = cell.w;
    target.h = cell.h;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(page);
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
