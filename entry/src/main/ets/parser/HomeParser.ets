import { HomeStats, emptyHomeStats } from '../model/HomeStats';
import { Html, HtmlNode } from './Html';

/** 图片配额块（My Home 第一块 `.homebox`）的两套官方文案（源 `EhHomeParser` 同样兼容）。 */
const LIMIT_RE: RegExp =
  /You are currently at ([\d,]+) towards (?:your account limit of|a limit of) ([\d,]+)/;
const RESET_NEW_RE: RegExp = /reset your image quota by spending ([\d,]+) GP/;
const RESET_OLD_RE: RegExp = /Reset Cost: ([\d,]+) GP/;

function toInt(raw: string): number {
  const n: number = Number.parseInt(raw.replace(/,/g, ''), 10);
  return isNaN(n) ? 0 : n;
}

/**
 * 解析 `home.php` 的图片配额（`used / total` + 重置 GP）。
 *
 * 站点两条文案都吃：
 * - `You are currently at X towards your account limit of Y.`（账号配额）
 * - `You are currently at X towards a limit of Y.`（旧文案 / IP 配额）
 * 拿不到数字但页面有配额块 → 视为「按 IP 限制」（`ipBased`），仍可展示。
 */
export class HomeParser {
  static parse(html: string): HomeStats {
    const root: HtmlNode = Html.parse(html);
    const boxes: HtmlNode[] = Html.select(root, '.homebox');
    if (boxes.length === 0) {
      return emptyHomeStats();
    }
    // 配额固定在第一个 homebox；空白归一化，避免换行打断正则。
    const text: string = Html.text(boxes[0]).replace(/\s+/g, ' ');
    // IP 额度文案没有数字，只有「You are currently using IP-based limits...」。
    if (text.indexOf('IP-based limits') >= 0) {
      return { ok: true, used: 0, total: 0, resetCost: 0, ipBased: true };
    }
    const match: RegExpExecArray | null = LIMIT_RE.exec(text);
    if (match === null) {
      return { ok: true, used: 0, total: 0, resetCost: 0, ipBased: true };
    }
    const used: number = toInt(match[1]);
    const total: number = toInt(match[2]);    const resetNew: RegExpExecArray | null = RESET_NEW_RE.exec(text);
    const resetOld: RegExpExecArray | null = RESET_OLD_RE.exec(text);
    const resetCost: number = resetNew !== null
      ? toInt(resetNew[1])
      : (resetOld !== null ? toInt(resetOld[1]) : 0);
    return {
      ok: true,
      used: used,
      total: total,
      resetCost: resetCost,
      ipBased: total <= 0
    };
  }
}
