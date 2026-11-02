/**
 * 搜索框的中文联想输入（纯函数；UI 在 `ui/SearchPage.ets`，候选来源 `tagdb/TagDb.search`）。
 *
 * 为什么只做「最后一个片段」：站点语法本身就是空格分隔的关键词列表，
 * 用户拼多标签是「选一个 → 空格 → 再输中文 → 再选」，因此联想必须能定位到**当前正在输入的词**，
 * 而不是只认整框中文。
 */

/** 待替换片段。[start, end) 是 UTF-16 码元下标，可直接喂给 `String.substring` / `replaceRange`。 */
export interface TagToken {
  start: number;
  end: number;
  word: string;
}

/**
 * 片段含中日文：统一表意（含扩展 A）/ 兼容表意 / 日文假名。
 * 只按 `charCodeAt` 比较 BMP 区间：这三个区都落在 BMP 内，不需要代理对处理；
 * 需要按码点走的话会引入「区间内码点 ≠ 区间内码元」的错位风险，而当前区间没有这个需求。
 */
function hasCjk(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if ((code >= 0x3400 && code <= 0x9fff) || (code >= 0xf900 && code <= 0xfaff) ||
      (code >= 0x3040 && code <= 0x30ff)) {
      return true;
    }
  }
  return false;
}

/** 空格分隔符（与站点 `f_search` 的分词一致：只有空白，不含标点）。 */
function isBlank(ch: string): boolean {
  // `\u3000` 是中文键盘/输入法常打出的全角空格：对用户来说就是空格，必须能和半角空格一样分词。
  return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' || ch === '\u3000';
}

/**
 * 取最后一个空白分隔、且含中日文的片段；没有则 `undefined`。
 *
 * 末尾空白先跳过：用户敲完「示例标签␣」准备接下一个词时，候选不该刚出现就消失；
 * 返回的 `end` 仍指向词尾，所以替换只动词、不动那个空格。
 * 纯英文 / 纯空白一律 `undefined`——英文输入不需要中文联想（拼音另立需求）。
 *
 * 前导 `-` / `~` **不算片段的一部分**：它们是查询语法（排除 / OR），不是标签内容。
 * 让 `start` 跳过它们，选中的替换就只会动「示例标签」，`-` 原地留下（`-female:"sample tags$"`）；
 * 若把前缀包进片段，既会把 `-示例标签` 当关键词去标签库搜（一条都搜不到），
 * 又会在拼回 `ns:"tag$"` 时丢掉否定符（`exactTagQuery` 注释里的前缀保留约定也要求这样）。
 */
export function trailingCjkToken(text: string): TagToken | undefined {
  let end: number = text.length;
  while (end > 0 && isBlank(text.charAt(end - 1))) {
    end--;
  }
  let start: number = end;
  while (start > 0 && !isBlank(text.charAt(start - 1))) {
    start--;
  }
  if (start === end) {
    return undefined;
  }
  const lead: string = text.charAt(start);
  if (lead === '-' || lead === '~') {
    start++;
  }
  const word: string = text.substring(start, end);
  if (!hasCjk(word)) {
    return undefined;
  }
  const token: TagToken = { start: start, end: end, word: word };
  return token;
}

/**
 * 用 `replacement` 替换 `[start, end)`，其余原样保留。
 * 不做越界收敛：调用方拿的区间来自 `trailingCjkToken`，错位属于逻辑错误，应该暴露而不是静默吞掉。
 */
export function replaceRange(text: string, start: number, end: number, replacement: string): string {
  return `${text.substring(0, start)}${replacement}${text.substring(end)}`;
}
