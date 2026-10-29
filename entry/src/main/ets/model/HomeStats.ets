/**
 * 图片配额（站点 `home.php` → My Home → Image Limits）。
 *
 * - `used` / `total`：当前用量 / 上限（站点原文数字，原样保留）；
 * - `resetCost`：花多少 GP 可重置（0 = 站点没给）；
 * - `ipBased`：按 IP 计（未登录 / 未绑定账号时站点不给上限数字）；
 * - `ok`：是否拿得到配额信息（未登录或页面不含配额块 = false）。
 */
export interface HomeStats {
  ok: boolean;
  used: number;
  total: number;
  resetCost: number;
  ipBased: boolean;
}

/** 未取得时的空值（调用方用它显示「登录后可查看」）。 */
export function emptyHomeStats(): HomeStats {
  return { ok: false, used: 0, total: 0, resetCost: 0, ipBased: false };
}
