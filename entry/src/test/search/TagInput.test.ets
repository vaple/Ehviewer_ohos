import { describe, it, expect } from '@ohos/hypium';
import { replaceRange, shouldSuggest, trailingToken, TagToken } from '../../main/ets/search/TagInput';

/**
 * 索引一律是 UTF-16 码元位置（与 `String.substring` 同一坐标系）：
 * 混合了英文标签与中文的查询里，按码点算会偏一位，替换时切进引号里。
 *
 * 样本词只用来验证「切词 / 拼接」的机械行为，用中性词（`示例标签` / `sample tags`），
 * 不承载任何真实标签内容。
 */
export default function tagInputTest() {
  describe('TagInput', () => {
    it('trailing_cjk_whole_query', 0, () => {
      const token: TagToken | undefined = trailingToken('示例标签');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(0);
        expect(token.end).assertEqual(4);
        expect(token.word).assertEqual('示例标签');
      }
    });

    it('trailing_cjk_after_exact_ascii_tag', 0, () => {
      // 触发条件只看「最后一个片段」，不是「整框都是中文」——多标签拼接才能接着输。
      const token: TagToken | undefined = trailingToken('female:"sample tags$" 长');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(22);
        expect(token.end).assertEqual(23);
        expect(token.word).assertEqual('长');
      }
    });

    it('trailing_cjk_kana_counts', 0, () => {
      const token: TagToken | undefined = trailingToken('big さくら');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(4);
        expect(token.end).assertEqual(7);
        expect(token.word).assertEqual('さくら');
      }
    });

    it('trailing_ascii_is_a_token_too', 0, () => {
      // 英文也要能联想（按 tag 前缀）。英文 tag 常自带空格，所以相邻的 ASCII 片段要并成一个词，
      // 否则 `big b` 只会拿着 `b` 去做前缀匹配。
      const token: TagToken | undefined = trailingToken('sample tags');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(0);
        expect(token.end).assertEqual(11);
        expect(token.word).assertEqual('sample tags');
      }
    });

    it('blank_is_undefined', 0, () => {
      expect(trailingToken('   ') === undefined).assertTrue();
      expect(trailingToken('') === undefined).assertTrue();
    });

    it('suggest_floor_is_one_cjk_or_two_latin', 0, () => {
      // 一个汉字足够具体；一个拉丁字母几乎是全集，不值得弹面板。
      expect(shouldSuggest('巨')).assertTrue();
      expect(shouldSuggest('示例')).assertTrue();
      expect(shouldSuggest('j')).assertFalse();
      expect(shouldSuggest('ju')).assertTrue();
      expect(shouldSuggest('sample tags')).assertTrue();
    });

    it('trailing_space_after_cjk_still_finds_token', 0, () => {
      // 用户敲完空格准备继续输入：此刻仍应给出上一个中文词的候选（面板不闪）。
      const token: TagToken | undefined = trailingToken('sample tags 示例标签 ');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(12);
        expect(token.end).assertEqual(16);
      }
    });

    it('only_last_segment_is_considered', 0, () => {
      // 语义是「**末尾**那一串」：前面的中文标签已经拼完，光标在英文上，候选按英文来；
      // 相邻 ASCII 片段并成一个词（`sample tags`），中文片段不并（那已经是另一个标签）。
      const token: TagToken | undefined = trailingToken('示例标签 sample tags');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(5);
        expect(token.end).assertEqual(16);
        expect(token.word).assertEqual('sample tags');
      }
    });

    it('ideographic_space_counts_as_separator', 0, () => {
      // 中文输入法/中文键盘常打出全角空格（U+3000）：它同样是分隔符，且必须留在片段之外。
      const token: TagToken | undefined = trailingToken('示例标签　');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(0);
        expect(token.end).assertEqual(4);
        expect(token.word).assertEqual('示例标签');
      }
    });

    it('trailing_cjk_strips_exclude_prefix', 0, () => {
      // `-` 是查询语法（排除），不是标签内容：片段从「示」开始，
      // 替换时 `-` 自然留在原位，语义不丢；同时送给标签库的关键词也不能带 `-`（否则一条都搜不到）。
      const token: TagToken | undefined = trailingToken('-示例标签');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(1);
        expect(token.end).assertEqual(5);
        expect(token.word).assertEqual('示例标签');
      }
    });

    it('trailing_cjk_strips_or_prefix', 0, () => {
      const token: TagToken | undefined = trailingToken('~示例标签');
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(1);
        expect(token.end).assertEqual(5);
        expect(token.word).assertEqual('示例标签');
      }
    });

    it('replace_keeps_prefix_and_trailing_space', 0, () => {
      // 组合语义：只换词本身 —— 前面的 `-` 与后面的空格都不动。
      const text: string = 'big -示例标签 ';
      const token: TagToken | undefined = trailingToken(text);
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(replaceRange(text, token.start, token.end, 'female:"sample tags$"'))
          .assertEqual('big -female:"sample tags$" ');
      }
    });

    it('replace_keeps_trailing_space_after_pick', 0, () => {
      // 选完后用户还要接着拼下一个词：末尾空格必须保留，否则光标一挪就粘住上一个标签。
      const text: string = 'sample tags 示例标签 ';
      const token: TagToken | undefined = trailingToken(text);
      expect(token === undefined).assertFalse();
      if (token !== undefined) {
        expect(token.start).assertEqual(12);
        expect(token.end).assertEqual(16);
        expect(replaceRange(text, token.start, token.end, 'female:"sample tags$"'))
          .assertEqual('sample tags female:"sample tags$" ');
      }
    });

    it('replace_range_keeps_rest_of_query', 0, () => {
      expect(replaceRange('female:"sample tags$" 长', 22, 23, 'female:"sample shoes$"'))
        .assertEqual('female:"sample tags$" female:"sample shoes$"');
    });

    it('replace_range_at_tail', 0, () => {
      expect(replaceRange('示例标签', 0, 4, 'female:"sample tags$"'))
        .assertEqual('female:"sample tags$"');
    });
  });
}
