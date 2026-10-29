/** 阅读方向。 */
export enum ReadingDirection {
  LTR,
  RTL,
  VERTICAL
}

/**
 * 页码索引映射。本模块内部页码统一 **0 起**（`page ∈ [0, total)`）。
 * RTL 时显示索引与页码相反（`display = total - 1 - page`）。
 */
export function toDisplayIndex(page: number, total: number, dir: ReadingDirection): number {
  if (dir === ReadingDirection.RTL) {
    return total - 1 - page;
  }
  return page;
}

/** `toDisplayIndex` 的逆运算。 */
export function toPage(displayIndex: number, total: number, dir: ReadingDirection): number {
  if (dir === ReadingDirection.RTL) {
    return total - 1 - displayIndex;
  }
  return displayIndex;
}

/**
 * 打开阅读器时的起始页：把持久化的进度收敛成合法页码（**0 起**）。
 * 进度缺失（`-1`）、越界（画廊页数变少/换画廊/数据损坏）或 `total <= 0` 时都从第 0 页开始。
 */
export function resolveStartPage(saved: number, total: number): number {
  if (total <= 0) {
    return 0;
  }
  return saved >= 0 && saved < total ? saved : 0;
}
