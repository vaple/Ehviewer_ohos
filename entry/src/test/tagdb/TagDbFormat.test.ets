import { describe, it, expect } from '@ohos/hypium';
import {
  escapeField, unescapeField, parseTagDb, peekFormat, translateTagOf, translateNsOf, introOf, searchTags, TAGDB_FORMAT
} from '../../main/ets/tagdb/TagDbFormat';

// 排序键 = ns + ':' + tag，必须严格递增：
// artist:some artist < female:big breasts < female:sole female < female:unnamed tag
// < male:big breasts < parody:some work
const FIXTURE: string =
  '#tagdb\t1\n' +
  '#source\tdeadbeef\t2026-11-01T00:00:00Z\n' +
  '#rows\n' +
  'rows\t内容索引\n' +
  'artist\t艺术家\n' +
  'female\t女性\n' +
  'male\t男性\n' +
  'parody\t原作\n' +
  '#tags\n' +
  'artist\tsome artist\t某画师\n' +
  'female\tbig breasts\t巨乳\n' +
  'female\tsole female\t单女\n' +
  'female\tunnamed tag\t未命名\n' +
  'male\tbig breasts\t巨乳（男）\n' +
  'parody\tsome work\t某作品\n' +
  '#intro\n' +
  'female\tbig breasts\t一般的大乳房。\\n\\n是超乳的前置标签。\n';

export default function tagDbFormatTest() {
  describe('TagDbFormat', () => {
    it('escapes_and_unescapes_roundtrip', 0, () => {
      const raw: string = 'a\\b\tc\nd\r';
      expect(unescapeField(escapeField(raw))).assertEqual('a\\b\tc\nd');
    });
    it('parses_header_and_counts', 0, () => {
      const db = parseTagDb(FIXTURE);
      expect(db.meta.format).assertEqual(TAGDB_FORMAT);
      expect(db.meta.sha).assertEqual('deadbeef');
      expect(db.keys.length).assertEqual(6);
      expect(db.nsNames.get('female')).assertEqual('女性');
    });
    it('rejects_unsorted_tags', 0, () => {
      // 把第一条的命名空间改成 zzz：key 从 artist:… 变成 zzz:…，后面的 female:… 就比它小了。
      let threw = false;
      try {
        parseTagDb(FIXTURE.replace('artist\tsome artist\t某画师', 'zzz\tsome artist\t某画师'));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
    it('rejects_wrong_format', 0, () => {
      let threw = false;
      try {
        parseTagDb(FIXTURE.replace('#tagdb\t1', '#tagdb\t9'));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
    it('translates_and_falls_back_to_raw', 0, () => {
      const db = parseTagDb(FIXTURE);
      expect(translateTagOf(db, 'female', 'big breasts')).assertEqual('巨乳');
      expect(translateTagOf(db, 'female', 'not in db')).assertEqual('not in db');
      expect(translateNsOf(db, 'parody')).assertEqual('原作');
      expect(translateNsOf(db, 'unknown')).assertEqual('unknown');
    });
    it('finds_first_and_last_key', 0, () => {
      const db = parseTagDb(FIXTURE);
      expect(translateTagOf(db, 'artist', 'some artist')).assertEqual('某画师');
      expect(translateTagOf(db, 'parody', 'some work')).assertEqual('某作品');
    });
    it('returns_empty_intro_when_absent', 0, () => {
      const db = parseTagDb(FIXTURE);
      expect(introOf(db, 'female', 'sole female')).assertEqual('');
      expect(introOf(db, 'female', 'big breasts')).assertEqual('一般的大乳房。\n\n是超乳的前置标签。');
    });
    it('ranks_exact_first_then_english_prefix', 0, () => {
      const db = parseTagDb(FIXTURE);
      const none = searchTags(db, '姐妹', 10);
      expect(none.length).assertEqual(0);
      const exact = searchTags(db, '巨乳', 10);
      expect(exact.length).assertEqual(2);
      expect(exact[0].ns).assertEqual('female');   // 名字完全相等（score 0）排在名字前缀（score 1）之前
      const en = searchTags(db, 'sole', 10);
      expect(en.length).assertEqual(1);
      expect(en[0].name).assertEqual('单女');
    });
    it('caps_results_at_limit', 0, () => {
      const db = parseTagDb(FIXTURE);
      // 「某」命中「某画师」「某作品」两条，limit=1 时只回一条（证明截断生效）。
      expect(searchTags(db, '某', 1).length).assertEqual(1);
    });
    // 以下是 brief 之外补的校验边界：解析器"该抛却没抛"时二分/回退会静默给错结果。
    it('rejects_duplicate_key', 0, () => {
      let threw = false;
      try {
        parseTagDb(FIXTURE.replace('female\tsole female\t单女', 'female\tbig breasts\t巨乳2'));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
    it('rejects_missing_segment', 0, () => {
      let threw = false;
      try {
        parseTagDb(FIXTURE.replace('#intro\nfemale\tbig breasts\t一般的大乳房。\\n\\n是超乳的前置标签。\n', ''));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
    it('rejects_raw_cr', 0, () => {
      // CRLF 文件会让每行末尾多一个不可见字符，译名里嵌 CR → 直接拒绝。
      let threw = false;
      try {
        parseTagDb(FIXTURE.replace('\n', '\r\n'));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
    it('translates_case_insensitively', 0, () => {
      const db = parseTagDb(FIXTURE);
      expect(translateTagOf(db, 'female', 'BIG BREASTS')).assertEqual('巨乳');
    });
    it('searches_nothing_for_blank_keyword', 0, () => {
      const db = parseTagDb(FIXTURE);
      expect(searchTags(db, '   ', 10).length).assertEqual(0);
    });
    // 加载器靠 peekFormat 区分「别的格式（忽略、不删）」与「坏文件（删除）」，
    // 所以只有「纯数字版本」才算认识的格式族，`1.0` / `v2` 一律 undefined。
    it('peeks_current_format_version', 0, () => {
      expect(peekFormat(FIXTURE)).assertEqual(TAGDB_FORMAT);
      expect(peekFormat('#tagdb\t2\n#tags\n')).assertEqual(2);
    });
    it('peek_rejects_non_numeric_or_missing_header', 0, () => {
      expect(peekFormat('#tagdb\t1.0\n')).assertUndefined();
      expect(peekFormat('#tagdb\tv2\n')).assertUndefined();
      expect(peekFormat('#source\tdeadbeef\t2026-11-01T00:00:00Z\n')).assertUndefined();
      expect(peekFormat('')).assertUndefined();
    });
  });
}
