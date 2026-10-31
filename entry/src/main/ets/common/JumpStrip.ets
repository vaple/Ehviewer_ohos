/**
 * 跳页条带的几何与分块数学（纯函数，可脱设备单测）。
 *
 * 为什么需要它：条带是「固定格宽 + 吸附居中」的定位器，页码由可视范围反推，不是由某个可滚动控件直接给出；
 * 而站点预览图按 20 页一块取（`?p=<page/20>`），所以「该看哪几块」必须由可视页范围算出来。
 */

/** 站点预览分块：每 20 页一块（与阅读器 token 分块同一语义）。 */
export const PREVIEW_CHUNK_PAGES: number = 20;
/** 条带格宽（vp）。 */
export const JUMP_STRIP_CELL_W: number = 78;
/** 格间距（vp）。 */
export const JUMP_STRIP_GAP: number = 8;
/** 可视窗距块边界多少格内预取相邻块。 */
export const JUMP_STRIP_EDGE_CELLS: number = 5;

export function chunkOfPage(page: number): number {
  return Math.floor(page / PREVIEW_CHUNK_PAGES);
}

/**
 * 可视页范围 `[start, end]` 覆盖到的块号（连续、含端点）。
 * 越界夹到 `[0, totalPages - 1]`；没有页时返回空数组（空画廊 / 详情还没回来）。
 */
export function chunksInRange(start: number, end: number, totalPages: number): number[] {
  if (totalPages <= 0) {
    return [];
  }
  const lastPage: number = totalPages - 1;
  const from: number = Math.max(0, Math.min(Math.min(start, end), lastPage));
  const to: number = Math.max(0, Math.min(Math.max(start, end), lastPage));
  const chunks: number[] = [];
  const firstChunk: number = chunkOfPage(from);
  const lastChunk: number = chunkOfPage(to);
  for (let chunk = firstChunk; chunk <= lastChunk; chunk++) {
    chunks.push(chunk);
  }
  return chunks;
}

/**
 * 可视窗贴近块边界时要提前取的相邻块（最多前、后各一块，不越界）。
 * 只贴近边界才预取：否则每次停稳都多拉 1–2 个请求，而用户可能根本没往那边滑。
 */
export function prefetchChunks(start: number, end: number, totalPages: number,
  edgeCells: number): number[] {
  if (totalPages <= 0 || edgeCells < 0) {
    return [];
  }
  const lastPage: number = totalPages - 1;
  const from: number = Math.max(0, Math.min(Math.min(start, end), lastPage));
  const to: number = Math.max(0, Math.min(Math.max(start, end), lastPage));
  const lastChunk: number = chunkOfPage(lastPage);
  const firstVisibleChunk: number = chunkOfPage(from);
  const lastVisibleChunk: number = chunkOfPage(to);
  const out: number[] = [];
  if (firstVisibleChunk > 0 && from - firstVisibleChunk * PREVIEW_CHUNK_PAGES <= edgeCells) {
    out.push(firstVisibleChunk - 1);
  }
  const visibleChunkLastPage: number = (lastVisibleChunk + 1) * PREVIEW_CHUNK_PAGES - 1;
  if (lastVisibleChunk < lastChunk && visibleChunkLastPage - to <= edgeCells) {
    out.push(lastVisibleChunk + 1);
  }
  return out;
}

/** 首尾各留多少 vp，第一格 / 最后一格才能滚到正中（给 `contentStartOffset` / `contentEndOffset`）。 */
export function centerSideOffset(viewportW: number, cellW: number): number {
  return Math.max(0, (viewportW - cellW) / 2);
}
