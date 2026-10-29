/**
 * 评论 meta 行的展示格式化（纯函数，Local 单测覆盖）。
 *
 * 站点原文是 `Posted on 29 October 2026, 14:53 by:`（2026-10 实抓确认），逐条显示完整月份名 + 时分
 * 会把 meta 行挤成两行。这里只留日期并重排成 `2026-10-29`：**不做时区换算**，年月日字段原样搬，
 * 也就不存在"按 UTC 解析、按本地显示"差一天的问题；解析不出来就原样返回，不猜。
 *
 * 不做相对时间（`3 天前`）：`Intl.RelativeTimeFormat` 只负责最后一步格式化，单位与阈值仍要自己定，
 * 而这条信息对用户价值低——用绝对日期换更少的代码与更少的口径。
 */
const MONTH_NAMES: string[] = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

/** `29 October 2026, 14:53`（时分可缺，日期是主体）。 */
const SITE_DATE: RegExp = new RegExp('^(\\d{1,2})\\s+([A-Za-z]+)\\s+(\\d{4})');
/** 已经是 ISO 形态的（如 `2026-01-02 03:04`）：只去掉时分。 */
const ISO_DATE: RegExp = new RegExp('^(\\d{4})-(\\d{1,2})-(\\d{1,2})');

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/** 站点时间原文 → `2026-10-29`（认不出来就原样返回）。 */
export function commentDateText(raw: string): string {
  const text: string = raw.trim();
  const m: RegExpMatchArray | null = text.match(SITE_DATE);
  if (m !== null) {
    const month: number = MONTH_NAMES.indexOf(m[2]);
    if (month < 0) {
      return text;
    }
    return `${m[3]}-${pad2(month + 1)}-${pad2(Number.parseInt(m[1], 10))}`;
  }
  const iso: RegExpMatchArray | null = text.match(ISO_DATE);
  if (iso !== null) {
    return `${iso[1]}-${pad2(Number.parseInt(iso[2], 10))}-${pad2(Number.parseInt(iso[3], 10))}`;
  }
  return text;
}

/** 分数展示：`+5` / `-3` / `0`；无分数回空串（调用方直接拼）。 */
export function commentScoreText(score: number | undefined): string {
  if (score === undefined) {
    return '';
  }
  return score > 0 ? `+${score}` : `${score}`;
}
