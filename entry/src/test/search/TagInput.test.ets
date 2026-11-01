import { describe, it, expect } from '@ohos/hypium';
import { replaceRange, trailingCjkToken, TagToken } from '../../main/ets/search/TagInput';

/**
 * 索引一律是 UTF-16 码元位置（与 `String.substring` 同一坐标系）：
 * 混合了英文标签与中文的查询里，按码点算会偏一位，替换时切进引号里。
 */
export default function tagInputTest() {
  describe('TagInput', () => {
    it('trailing_cjk_whole_query', 0, () => {
      const token: TagToken | undefined = trailingCjkToken('巨乳');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(0);
        expect(token.end).assertEqual(2);
        expect(token.word).assertEqual('巨乳');
      }
    });

    it('trailing_cjk_after_exact_ascii_tag', 0, () => {
      // 触发条件只看「最后一个片段含中日文」，不是「整框都是中文」——多标签拼接才能接着输。
      const token: TagToken | undefined = trailingCjkToken('female:"big breasts$" 长');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(22);
        expect(token.end).assertEqual(23);
        expect(token.word).assertEqual('长');
      }
    });

    it('trailing_cjk_kana_counts', 0, () => {
      const token: TagToken | undefined = trailingCjkToken('big ちんぽ');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(4);
        expect(token.end).assertEqual(7);
        expect(token.word).assertEqual('ちんぽ');
      }
    });

    it('trailing_ascii_only_is_undefined', 0, () => {
      expect(trailingCjkToken('big breasts') === undefined).assertTrue();
    });

    it('blank_is_undefined', 0, () => {
      expect(trailingCjkToken('   ') === undefined).assertTrue();
      expect(trailingCjkToken('') === undefined).assertTrue();
    });

    it('trailing_space_after_cjk_still_finds_token', 0, () => {
      // 用户敲完空格准备继续输入：此刻仍应给出上一个中文词的候选（面板不闪）。
      const token: TagToken | undefined = trailingCjkToken('big breasts 巨乳 ');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(12);
        expect(token.end).assertEqual(14);
      }
    });

    it('earlier_cjk_segment_does_not_trigger', 0, () => {
      // 语义必须是「**末尾**片段」：`巨乳 big breasts` 正在打英文，不该弹中文候选。
      expect(trailingCjkToken('巨乳 big breasts') === undefined).assertTrue();
    });

    it('ideographic_space_counts_as_separator', 0, () => {
      // 中文输入法/中文键盘常打出全角空格（U+3000）：它同样是分隔符，且必须留在片段之外。
      const token: TagToken | undefined = trailingCjkToken('巨乳　');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(0);
        expect(token.end).assertEqual(2);
        expect(token.word).assertEqual('巨乳');
      }
    });

    it('trailing_cjk_strips_exclude_prefix', 0, () => {
      // `-` 是查询语法（排除），不是标签内容：片段从「巨」开始，
      // 替换时 `-` 自然留在原位，语义不丢；同时送给标签库的关键词也不能带 `-`（否则一条都搜不到）。
      const token: TagToken | undefined = trailingCjkToken('-巨乳');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(1);
        expect(token.end).assertEqual(3);
        expect(token.word).assertEqual('巨乳');
      }
    });

    it('trailing_cjk_strips_or_prefix', 0, () => {
      const token: TagToken | undefined = trailingCjkToken('~巨乳');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(1);
        expect(token.end).assertEqual(3);
        expect(token.word).assertEqual('巨乳');
      }
    });

    it('replace_keeps_prefix_and_trailing_space', 0, () => {
      // 组合语义：只换词本身 —— 前面的 `-` 与后面的空格都不动。
      const text: string = 'big -巨乳 ';
      const token: TagToken | undefined = trailingCjkToken(text);
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(replaceRange(text, token.start, token.end, 'female:"big breasts$"'))
          .assertEqual('big -female:"big breasts$" ');
      }
    });

    it('replace_keeps_trailing_space_after_pick', 0, () => {
      // 选完后用户还要接着拼下一个词：末尾空格必须保留，否则光标一挪就粘住上一个标签。
      const text: string = 'big breasts 巨乳 ';
      const token: TagToken | undefined = trailingCjkToken(text);
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(12);
        expect(token.end).assertEqual(14);
        expect(replaceRange(text, token.start, token.end, 'female:"big breasts$"'))
          .assertEqual('big breasts female:"big breasts$" ');
      }
    });

    it('replace_range_keeps_rest_of_query', 0, () => {
      expect(replaceRange('female:"big breasts$" 长', 22, 23, 'female:"thighhighs$"'))
        .assertEqual('female:"big breasts$" female:"thighhighs$"');
    });

    it('replace_range_at_tail', 0, () => {
      expect(replaceRange('巨乳', 0, 2, 'female:"big breasts$"'))
        .assertEqual('female:"big breasts$"');
    });
  });
}
