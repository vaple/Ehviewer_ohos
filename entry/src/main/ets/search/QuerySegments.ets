/**
 * 搜索条件的「已确认 / 草稿」两段模型（纯函数；UI 在 `ui/SearchPage.ets`）。
 *
 * 为什么拆两段：`f_search` 是空格分隔的条件列表。若把最终串整段留在输入框里，
 * 条件越多框越长、光标永远要手动挪到末尾，而且英文标签自带空格（`big breasts`），
 * 「空格成词」会把它拆成两个条件。现在输入框只放**正在输入的草稿**，
 * 回车 / 点「＋」/ 点候选才把草稿转成一条 chip，最终查询串由 `joinQueryText` 拼出来。
 */

import { exactTagQuery } from './SearchQuery';

/**
 * 空格切词（引号内的空格不切：`-other:"ai generated"` 算一个条件）。
 * 只用于**回填**（路由参数 / 快搜记录 → chips），不再跟着输入框实时切词。
 */
export function splitQueryTokens(text: string): string[] {
  const out: string[] = [];
  const src: string = text.trim();
  let cur: string = '';
  let inQuote: boolean = false;
  for (let i = 0; i < src.length; i++) {
    const ch: string = src.charAt(i);
    if (ch === '"') {
      inQuote = !inQuote;
      cur += ch;
      continue;
    }
    if (ch === ' ' && !inQuote) {
      if (cur.length > 0) {
        out.push(cur);
        cur = '';
      }
      continue;
    }
    cur += ch;
  }
  if (cur.length > 0) {
    out.push(cur);
  }
  return out;
}

/**
 * 拼回 `f_search` 主体：已确认条件在前、草稿在后，各自 trim，空串不占位。
 *
 * 必须 trim：草稿是输入框原样文本，用户很容易在词尾留空格；
 * 不 trim 就会拼出 `a  b`（双空格），回填 chip 时会多出一个空 token。
 * 也不能给草稿补引号 / 改语法：用户可能正在手写 `uploader:"名字"` 这类条件，替它规范化会改坏输入。
 */
export function joinQueryText(segments: string[], draft: string): string {
  const parts: string[] = [];
  for (let i = 0; i < segments.length; i++) {
    const token: string = segments[i].trim();
    if (token.length > 0) {
      parts.push(token);
    }
  }
  const tail: string = draft.trim();
  if (tail.length > 0) {
    parts.push(tail);
  }
  return parts.join(' ');
}

/**
 * 草稿 → 已确认条件（返回新数组：`@Local` 靠整体替换刷新，原地 `push` 不触发重绘）。
 * 空草稿原样返回同一个数组，调用方可用引用相等判断「没变化」。
 * 只 trim 首尾，不改写内容——那是用户自己敲的条件。
 */
export function appendDraft(segments: string[], draft: string): string[] {
  const token: string = draft.trim();
  if (token.length === 0) {
    return segments;
  }
  return segments.concat([token]);
}

/**
 * 草稿的前导语法前缀：`-` = 排除、`~` = OR。
 * 它是**查询语法**而不是标签内容，`exactTagQuery` 只处理 `namespace:value` 部分，
 * 所以点候选时必须在这里显式取出来再拼回去（旧模型靠 `replaceRange` 天然保留）。
 */
export function draftPrefix(draft: string): string {
  const src: string = draft.trim();
  const lead: string = src.length > 0 ? src.charAt(0) : '';
  return lead === '-' || lead === '~' ? lead : '';
}

/**
 * 点候选 → 待入列的条件串：`namespace:"tag$"` 精确语法 + 草稿保留的 `-`/`~` 前缀。
 * 例：草稿 `-示例` 选中 `ns:x` → `-ns:"x$"`（排除整个标签，而不是排除一个裸关键词）。
 */
export function suggestionChip(draft: string, namespace: string, tag: string): string {
  return `${draftPrefix(draft)}${exactTagQuery(`${namespace}:${tag}`)}`;
}
