import { describe, it, expect } from '@ohos/hypium';
import {
  appendDraft, draftPrefix, joinQueryText, splitQueryTokens, suggestionChip
} from '../../main/ets/search/QuerySegments';

/**
 * 搜索页的「已确认条件 / 草稿」模型（`search/QuerySegments`）。
 * 这里断的是**发出去的 `f_search` 与 chip 的内容**，不是 UI：纯函数行为即断言。
 */
export default function querySegmentsTest() {
  describe('QuerySegments', () => {
    it('join_query_text_trims_and_skips_empty', 0, () => {
      // 前后空格必须吃掉：草稿是输入框原样文本，用户很容易在词尾留空格，
      // 不 trim 会拼出双空格，回填 chip 时多出空 token。
      expect(joinQueryText(['a', ' b '], '  c ')).assertEqual('a b c');
      expect(joinQueryText([], '   ')).assertEqual('');
      expect(joinQueryText([' x '], '')).assertEqual('x');
      // 条件顺序 = 入列顺序 + 草稿在末尾（用户最后输入的排在最后）。
      expect(joinQueryText(['-female:"x$"', 'big breasts'], '巨乳'))
        .assertEqual('-female:"x$" big breasts 巨乳');
    });

    it('append_draft_trims_and_keeps_raw_text', 0, () => {
      const seg: string[] = ['a'];
      const next: string[] = appendDraft(seg, '  female:"x$"  ');
      expect(next.length).assertEqual(2);
      expect(next[0]).assertEqual('a');
      // 只 trim 首尾，不改写内容：用户手写的 qualifier 必须原样入列。
      expect(next[1]).assertEqual('female:"x$"');
      // 空草稿不产生空 chip，并原样返回同一个数组（UI 用引用相等判断「没变化」）。
      expect(appendDraft(seg, '   ') === seg).assertTrue();
    });

    it('suggestion_chip_keeps_draft_prefix', 0, () => {
      // 前缀 `-`/`~` 是查询语法，不属于标签内容：点候选后必须仍在最前面。
      expect(suggestionChip('-示例', 'ns', 'x')).assertEqual('-ns:"x$"');
      expect(suggestionChip('~示例', 'ns', 'x')).assertEqual('~ns:"x$"');
      expect(suggestionChip('示例', 'ns', 'x')).assertEqual('ns:"x$"');
      // 已有精确语法时幂等（重复选同一条不会叠引号）。
      expect(suggestionChip('-ns:"x$"', 'ns', 'x')).assertEqual('-ns:"x$"');
      expect(draftPrefix(' -示例')).assertEqual('-');
      expect(draftPrefix('示例')).assertEqual('');
    });

    it('split_query_tokens_roundtrip', 0, () => {
      // 引号内的空格不拆：`-other:"ai generated"` 是一条条件，不是两条。
      const tokens: string[] = splitQueryTokens('  -other:"ai generated"  巨乳  ');
      expect(tokens.length).assertEqual(2);
      expect(tokens[0]).assertEqual('-other:"ai generated"');
      expect(tokens[1]).assertEqual('巨乳');
      // 回填：切出来的条件拼回去与原文等价（空格归一）。
      expect(joinQueryText(tokens, '')).assertEqual('-other:"ai generated" 巨乳');
      // 空串 / 纯空白 → 没有 chip（而不是一个空 chip）。
      expect(splitQueryTokens('   ').length).assertEqual(0);
    });
  });
}
