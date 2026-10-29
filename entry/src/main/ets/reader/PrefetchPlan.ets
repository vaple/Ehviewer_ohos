/** 预取窗口计算（纯函数，无副作用）。
 * 阅读器内部页码 **0 起**，区间均为闭区间。
 */

/** 预加载页数可配置范围（设置页两个滑块共用）。 */
export const PREFETCH_MIN: number = 0;
export const PREFETCH_MAX: number = 10;

/** 预加载页数夹取（非法值回 0；小数四舍五入）。 */
export function clampPrefetch(value: number): number {
  if (!Number.isFinite(value)) {
    return PREFETCH_MIN;
  }
  return Math.max(PREFETCH_MIN, Math.min(PREFETCH_MAX, Math.round(value)));
}

/** 当前页前后各取若干页（去掉自身与越界）；顺序为「先前、后后」。 */
export function neighbors(page: number, total: number, ahead: number, behind: number): number[] {
  const out: number[] = [];
  for (let d = 1; d <= ahead; d++) {
    const p: number = page + d;
    if (p < total) {
      out.push(p);
    }
  }
  for (let d = 1; d <= behind; d++) {
    const p: number = page - d;
    if (p >= 0) {
      out.push(p);
    }
  }
  return out;
}

/** 可见区间 `[start, end]` 向两侧扩 `margin` 后的页号列表（升序，已夹取到 `[0, total)`）。 */
export function range(start: number, end: number, total: number, margin: number): number[] {
  const from: number = Math.max(0, start - margin);
  const to: number = Math.min(total - 1, end + margin);
  const out: number[] = [];
  for (let p = from; p <= to; p++) {
    out.push(p);
  }
  return out;
}
