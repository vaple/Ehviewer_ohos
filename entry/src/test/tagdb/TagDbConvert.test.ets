import { describe, it, expect } from '@ohos/hypium';
import { dbJsonToTsv } from '../../main/ets/tagdb/TagDbConvert';
import { introOf, parseTagDb, translateNsOf, translateTagOf, unescapeField, TagDbData } from '../../main/ets/tagdb/TagDbFormat';
import { CONVERT_DOC_JSON, GOLDEN_BUILT_AT, GOLDEN_TSV } from '../fixtures/tagdb/golden';

/**
 * `dbJsonToTsv` 的契约（spec §2.2）：产物必须能被 `parseTagDb` 原样接受，且转义/排序/丢弃规则与
 * `tools/tagdb/build_tagdb.py` 一致——否则内置快照没事、设备端更新后却写坏。
 *
 * 样本 JSON 与黄金 TSV 都在 `fixtures/tagdb/`：2 个命名空间；`some artist` 的 intro 含换行、
 * `sample tags` 的译名含 TAB、`back\slash` 的译名含反斜杠；另外两条故意没有可用译名（空串 / 全空白），
 * `links` / `description` 属于该丢弃的上游元数据。
 */

const SHA: string = 'abcdef0123456789abcdef0123456789abcdef01';
const BUILT_AT: string = '2026-11-02T09:30:00Z';

/** 取某一段（含段头之后、下一个段头之前）的行。 */
function linesOf(tsv: string, header: string): string[] {
  const lines: string[] = tsv.split('\n');
  const out: string[] = [];
  let inside: boolean = false;
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i];
    if (line.startsWith('#')) {
      inside = line === header;
      continue;
    }
    if (inside && line.length > 0) {
      out.push(line);
    }
  }
  return out;
}

export default function tagDbConvertTest() {
  describe('TagDbConvert', () => {
    it('emits_header_source_and_section_order', 0, () => {
      const tsv: string = dbJsonToTsv(CONVERT_DOC_JSON, BUILT_AT);
      expect(tsv.startsWith('#tagdb\t1\n')).assertTrue();
      const lines: string[] = tsv.split('\n');
      expect(lines[1]).assertEqual(`#source\t${SHA}\t${BUILT_AT}`);
      // 段落顺序是生成端契约（python 的 validate 只允许这一种写法）。
      const rowsAt: number = tsv.indexOf('\n#rows\n');
      const tagsAt: number = tsv.indexOf('\n#tags\n');
      const introAt: number = tsv.indexOf('\n#intro\n');
      expect(rowsAt > 0).assertTrue();
      expect(tagsAt > rowsAt).assertTrue();
      expect(introAt > tagsAt).assertTrue();
      // 只有一个末尾换行，没有空行、没有 BOM、没有 CR。
      expect(tsv.endsWith('\n')).assertTrue();
      expect(tsv.endsWith('\n\n')).assertFalse();
      expect(tsv.startsWith('\ufeff')).assertFalse();
      expect(tsv.indexOf('\r')).assertEqual(-1);
    });

    it('escapes_every_field_into_one_line', 0, () => {
      const tsv: string = dbJsonToTsv(CONVERT_DOC_JSON, BUILT_AT);
      // #tags 每行恰好 3 列 —— 译名里的 TAB 必须已转义，否则会多出一列。
      const tagLines: string[] = linesOf(tsv, '#tags');
      expect(tagLines.length).assertEqual(4);
      for (let i = 0; i < tagLines.length; i++) {
        expect(tagLines[i].split('\t').length).assertEqual(3);
      }
      expect(tsv.indexOf('female\tsample tags\t示\\t例') >= 0).assertTrue();
      expect(tsv.indexOf('artist\tsome artist\t某画师') >= 0).assertTrue();
      // 换行落在 #intro 段，必须是字面 `\n` 而不是真的换行。
      const introLines: string[] = linesOf(tsv, '#intro');
      expect(introLines.length).assertEqual(1);
      expect(introLines[0]).assertEqual('artist\tsome artist\t第一行\\n第二行');
    });

    it('sorts_tags_by_key_regardless_of_json_order', 0, () => {
      const tsv: string = dbJsonToTsv(CONVERT_DOC_JSON, BUILT_AT);
      const keys: string[] = [];
      const tagLines: string[] = linesOf(tsv, '#tags');
      for (let i = 0; i < tagLines.length; i++) {
        const cols: string[] = tagLines[i].split('\t');
        keys.push(`${unescapeField(cols[0])}:${unescapeField(cols[1])}`);
      }
      expect(keys[0]).assertEqual('artist:aaa artist');
      expect(keys[1]).assertEqual('artist:back\\slash tag');
      expect(keys[2]).assertEqual('artist:some artist');
      expect(keys[3]).assertEqual('female:sample tags');
    });

    it('roundtrips_through_parseTagDb', 0, () => {
      const tsv: string = dbJsonToTsv(CONVERT_DOC_JSON, BUILT_AT);
      const db: TagDbData = parseTagDb(tsv);
      expect(db.meta.sha).assertEqual(SHA);
      expect(db.meta.builtAt).assertEqual(BUILT_AT);
      expect(db.keys.length).assertEqual(4);
      expect(translateNsOf(db, 'artist')).assertEqual('艺术家');
      expect(translateNsOf(db, 'female')).assertEqual('女性');
      expect(translateTagOf(db, 'female', 'sample tags')).assertEqual('示\t例');
      expect(translateTagOf(db, 'artist', 'back\\slash tag')).assertEqual('反\\斜杠');
      expect(introOf(db, 'artist', 'some artist')).assertEqual('第一行\n第二行');
      // 没有可用译名的条目必须整条丢弃（包括它的释义）：命中空串会把界面上的标签抹成空白。
      expect(translateTagOf(db, 'female', 'empty name')).assertEqual('empty name');
      expect(translateTagOf(db, 'female', 'no name')).assertEqual('no name');
      expect(introOf(db, 'female', 'empty name')).assertEqual('');
    });

    it('keeps_namespace_rows_in_upstream_order', 0, () => {
      const tsv: string = dbJsonToTsv(CONVERT_DOC_JSON, BUILT_AT);
      const rows: string[] = linesOf(tsv, '#rows');
      expect(rows.length).assertEqual(2);
      expect(rows[0]).assertEqual('artist\t艺术家');
      expect(rows[1]).assertEqual('female\t女性');
    });

    it('skips_rows_pseudo_namespace_tags', 0, () => {
      // `rows` 是上游的命名空间索引：只该出现在 #rows，混进 #tags 会被当成 `rows:artist` 这种假标签，
      // 而且 `parseTagDb` 不会拒绝（key 合法、有序）——所以这条用例是唯一防线。
      const json: string =
        `{"head":{"sha":"${SHA}"},"data":[` +
        `{"namespace":"rows","frontMatters":{"name":"内容索引"},"data":{"artist":{"name":"画师"}}},` +
        `{"namespace":"female","frontMatters":{"name":"女性"},"data":{"x":{"name":"某"}}}]}`;
      const tsv: string = dbJsonToTsv(json, BUILT_AT);
      const db: TagDbData = parseTagDb(tsv);
      expect(db.keys.length).assertEqual(1);
      expect(db.keys[0]).assertEqual('female:x');
      expect(db.nsNames.get('rows')).assertEqual('内容索引');
      const tagLines: string[] = linesOf(tsv, '#tags');
      expect(tagLines.length).assertEqual(1);
    });

    it('sorts_by_raw_key_not_escaped_key', 0, () => {
      // 反例：`a<TAB>b` vs `a!b`。原始码元序 0x09 < 0x21；先转义再排会变成 `a\tb`（0x5C）> `a!b`。
      // 解析端按未转义 key 校验递增，所以排错时 `parseTagDb` 会直接抛错，或者顺序与预期相反。
      const json: string =
        `{"head":{"sha":"${SHA}"},"data":[{"namespace":"female","frontMatters":{"name":"女性"},` +
        `"data":{"a\\tb":{"name":"制表符"},"a!b":{"name":"感叹号"}}}]}`;
      const tsv: string = dbJsonToTsv(json, BUILT_AT);
      const db: TagDbData = parseTagDb(tsv);
      expect(db.keys.length).assertEqual(2);
      expect(db.keys[0]).assertEqual('female:a\tb');
      expect(db.keys[1]).assertEqual('female:a!b');
      // 文件里仍是单行：TAB 被转义成字面 `\t`，没有多出一列。
      const tagLines: string[] = linesOf(tsv, '#tags');
      expect(tagLines.length).assertEqual(2);
      expect(tagLines[0].split('\t').length).assertEqual(3);
    });

    it('treats_null_name_and_intro_as_empty', 0, () => {
      // Python 生成器用 `or ""` 把 null 当空串（译名空 → 整条丢弃；释义空 → 不写 #intro）。
      const json: string =
        `{"head":{"sha":"${SHA}"},"data":[{"namespace":"female","frontMatters":{"name":null},` +
        `"data":{"a":{"name":"甲","intro":null},"b":{"name":null,"intro":"丢弃"}}}]}`;
      const tsv: string = dbJsonToTsv(json, BUILT_AT);
      const db: TagDbData = parseTagDb(tsv);
      expect(db.nsNames.get('female')).assertEqual('');
      expect(db.keys.length).assertEqual(1);
      expect(db.keys[0]).assertEqual('female:a');
      expect(introOf(db, 'female', 'a')).assertEqual('');
    });

    it('throws_on_invalid_json', 0, () => {
      let threw: boolean = false;
      try {
        dbJsonToTsv('not json at all', BUILT_AT);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('throws_when_head_sha_missing', 0, () => {
      let threw: boolean = false;
      try {
        dbJsonToTsv('{"head":{},"data":[]}', BUILT_AT);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('throws_when_no_tags_survive', 0, () => {
      const json: string =
        `{"head":{"sha":"${SHA}"},"data":[{"namespace":"female","frontMatters":{"name":"女性"},` +
        `"data":{"x":{"name":"  "}}}]}`;
      let threw: boolean = false;
      try {
        dbJsonToTsv(json, BUILT_AT);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('formats_built_at_as_iso_utc_seconds', 0, () => {
      // 默认时间必须是定长 ISO8601 UTC（不带毫秒）：加载器按字典序比较新鲜度。
      const tsv: string = dbJsonToTsv(CONVERT_DOC_JSON);
      const source: string[] = tsv.split('\n')[1].split('\t');
      expect(source.length).assertEqual(3);
      expect(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(source[2])).assertTrue();
    });

    it('matches_python_generator_golden', 0, () => {
      // Python 生成器（发版产物）与 ArkTS 转换器（设备端更新）是两套独立实现，规则必须逐字一致。
      // 黄金样本由 `python scripts/tagdb/gen_golden.py` 从同一份 `fixtures/tagdb/convert_doc.json` 生成：
      // 任一侧单独改了转义顺序 / 丢弃规则 / 排序键 / 段顺序，这条用例立刻变红。
      expect(dbJsonToTsv(CONVERT_DOC_JSON, GOLDEN_BUILT_AT)).assertEqual(GOLDEN_TSV);
      // 顺带确认黄金样本本身是可加载的（不是只对了个字符串）。
      const db: TagDbData = parseTagDb(GOLDEN_TSV);
      expect(db.meta.builtAt).assertEqual(GOLDEN_BUILT_AT);
      expect(translateTagOf(db, 'female', 'sample tags')).assertEqual('示\t例');
      expect(translateTagOf(db, 'artist', 'back\\slash tag')).assertEqual('反\\斜杠');
    });
  });
}
