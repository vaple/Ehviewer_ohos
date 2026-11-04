/**
 * 详情页预览网格的「值不值得取」判据（纯函数，可脱设备单测）。
 *
 * 为什么用「屏/秒」而不是「行/秒」或固定 px：一屏能放多少行随屏高/缩略图比例变化，
 * 同一个「行/秒」在 9 行屏和 18 行折叠屏上，用户感知的速度差一倍。
 * 用「内容每秒走过几个视口高度」归一化后，判据等价于「一屏内容在眼前停留多久」：
 *
 *     一行的停留时长 T = 1 / (屏/秒)
 *
 * 所以「停留 ≥ 650ms」与「速度 ≤ 1.5 屏/秒」是同一条规则，只是单位不同。
 */

/** 速度采样窗（ms）：只在采样窗结束时算一次平均速度，不逐帧判断。 */
export const SPEED_SAMPLE_MS: number = 200;

/**
 * 允许取块的速度上限（屏/秒）。
 * 1.5 屏/秒 ⇔ 一屏在眼前停留约 650ms ⇔ 9 行屏约 13.5 行/s、18 行折叠屏约 27 行/s
 * （两者每行的停留时间相同，这正是「按屏归一化」的意义）。
 */
export const MAX_LOAD_SCREENS_PER_SECOND: number = 1.5;

/**
 * 内容移动速度（屏/秒）。
 * `deltaVp` / `viewportVp` 都是 vp（`currentOffset()` 与 `onAreaChange` 的官方单位一致），
 * 比值无量纲；视口或时间窗无效时返回 0（视为「没在动」，由调用方决定是否取）。
 */
export function screensPerSecond(deltaVp: number, viewportVp: number, dtMs: number): number {
  if (viewportVp <= 0 || dtMs <= 0) {
    return 0;
  }
  const screens: number = Math.abs(deltaVp) / viewportVp;
  return screens / (dtMs / 1000);
}

/** 当前速度下是否值得取块（等于「停留够久」）。 */
export function shouldLoadAtSpeed(speedScreensPerSecond: number): boolean {
  return speedScreensPerSecond <= MAX_LOAD_SCREENS_PER_SECOND;
}
