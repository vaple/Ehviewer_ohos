/** 缩放范围。 */
export const ZOOM_MIN: number = 1;
export const ZOOM_MAX: number = 4;

/** 捏合：按倍数缩放并夹取到 `[min, max]`。 */
export function applyPinch(current: number, factor: number, min: number, max: number): number {
  const next: number = current * factor;
  return Math.min(max, Math.max(min, next));
}

/** 双击：已放大则复位到 `ZOOM_MIN`，否则放到 `max`。 */
export function nextDoubleTapScale(current: number, max: number): number {
  return current > ZOOM_MIN ? ZOOM_MIN : max;
}

/** 平移夹取：放大 `scale` 倍后，可移动范围为 `±viewSize * (scale - 1) / 2`。 */
export function clampOffset(offset: number, viewSize: number, scale: number): number {
  const limit: number = Math.max(0, (viewSize * (scale - 1)) / 2);
  return Math.min(limit, Math.max(-limit, offset));
}
