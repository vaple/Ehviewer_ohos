/** 缩放范围。 */
export const ZOOM_MIN: number = 1;
/** 捏合上限（官方 `Scroll` 的 `maxZoomScale`）。双击**不**用这个值，见 `DOUBLE_TAP_SCALE`。 */
export const ZOOM_MAX: number = 4;

/**
 * 双击放大的默认倍率。
 *
 * 为什么不直接用 `ZOOM_MAX`：双击一下就顶到 4 倍太猛，而且顶到上限后再也无法继续放大 ——
 * 双击只负责给一个舒服的默认值，想要更大让用户自己捏（捏合上限仍是 `ZOOM_MAX`）。
 */
export const DOUBLE_TAP_SCALE: number = 2;

/** 捏合：按倍数缩放并夹取到 `[min, max]`。 */
export function applyPinch(current: number, factor: number, min: number, max: number): number {
  const next: number = current * factor;
  return Math.min(max, Math.max(min, next));
}

/**
 * 双击：已放大则复位到 `ZOOM_MIN`，否则放到 `target`。
 *
 * `target` 传 `DOUBLE_TAP_SCALE`（不是 `ZOOM_MAX`）；「只要 > 1 就复位」的语义保持一致，
 * 所以用户在 3 倍时双击也是退出，而不是调到 2 倍。
 */
export function nextDoubleTapScale(current: number, target: number): number {
  return current > ZOOM_MIN ? ZOOM_MIN : target;
}

/**
 * 单击切操作栏的最短延迟（ms）。
 *
 * 为什么要这么长：`TapGesture` 判定双击的窗口是**两次抬起之间 300ms**（SDK `gesture.d.ts` 明文）。
 * 单击处理必须晚于这个窗口，否则一次稍慢的双击会先让单击的定时器跑完（操作栏真切了一次），
 * 随后双击再 `cancelImmersiveSoon` 就来不及了 —— 表现是"双击顺带闪一下操作栏"。
 * 多出的 30ms 是给帧调度抖动的余量，观感上仍属即时响应。
 */
export const IMMERSIVE_DELAY_MS: number = 330;

/** SDK 的 `TapGesture` 双击窗口（ms）：两次抬起之间的超时。 */
export const DOUBLE_TAP_WINDOW_MS: number = 300;

/**
 * 单击延迟是否安全（必须严格大于双击窗口）。
 * 单独抽出来是为了让单测盯住这条约束：把它改小到窗口以内就会红。
 */
export function isImmersiveDelaySafe(delayMs: number, windowMs: number = DOUBLE_TAP_WINDOW_MS): boolean {
  return delayMs > windowMs;
}

/**
 * 手势偏移 → 屏幕平移量。
 *
 * `PanGesture.offsetX/Y` 报的是**组件局部坐标**（已含 `scale()` 变换）：scale=4 时手指走 705.88vp、
 * 回调只给 176.22vp（真机实测比值恒为 1/scale）；而 `.translate()` 作用于屏幕空间 1:1。
 * 直接把回调值喂给 `translate` 会让拖动慢 `scale` 倍 —— 表现为"放大后基本拖不动、到不了边"。
 */
export function panTranslate(offset: number, scale: number): number {
  return offset * scale;
}

/**
 * 平移夹取：可移动范围 = `(缩放后的绘制尺寸 − 视口) / 2`，按轴各自算。
 *
 * 为什么不用 `viewSize * (scale - 1) / 2`（容器尺寸）：`ImageFit.Contain` 下图片在留黑的轴上是
 * **比容器小**的，按容器夹取会允许拖出真图 —— 真机实测放大后连续上拖能露出整块黑边。
 * `content` 取 `Image.onComplete` 的 `contentWidth/Height`（未缩放的实际绘制尺寸）。
 * 未拿到 content（首帧/加载失败）时退回容器尺寸，此时 `scale=1` 区间为 0，等同"不许动"。
 */
export function clampOffset(offset: number, viewSize: number, content: number, scale: number): number {
  const drawn: number = (content > 0 ? content : viewSize) * scale;
  const limit: number = Math.max(0, (drawn - viewSize) / 2);
  return Math.min(limit, Math.max(-limit, offset));
}
