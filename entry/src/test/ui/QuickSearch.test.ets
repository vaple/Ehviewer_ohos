import { describe, it, expect } from '@ohos/hypium';
import { hasSavedKeyword, historyIdsToPrune, quickSearchToParam, quickSearchSummary, sameSearch } from '../../main/ets/search/QuickSearchQuery';
import { QuickSearch } from '../../main/ets/model/QuickSearch';
import { ALL_CATS } from '../../main/ets/search/SearchQuery';
import { joinQueryText, splitQueryTokens } from '../../main/ets/search/QuerySegments';

function row(keyword: string): QuickSearch {
  return {
    id: 1, category: 0, keyword: keyword, language: '',
    advanceSearch: 0, minRating: -1, time: 0, saved: 1
  };
}

export default function quickSearchTest() {
  describe('QuickSearchQuery', () => {
    it('hasSavedKeyword_matches_case_insensitive', 0, () => {
      expect(hasSavedKeyword([row('Soutsa')], 'soutsa')).assertTrue();
      expect(hasSavedKeyword([row('Soutsa')], 'naruto')).assertFalse();
      expect(hasSavedKeyword([], 'soutsa')).assertFalse();
    });

    it('quickSearchToParam_restores_conditions', 0, () => {
      const rec: QuickSearch = {
        id: 1, category: 0x2, keyword: 'nico', language: '',
        advanceSearch: 3, minRating: 4, time: 0, saved: 1
      };
      const param = quickSearchToParam(rec);
      expect(param.query).assertEqual('nico');
      expect(param.kind).assertEqual('keyword');
      expect(param.selectedBits !== undefined && param.selectedBits.indexOf(0x2) < 0).assertTrue();
      expect(param.scopes !== undefined && param.scopes.length).assertEqual(2);
      expect(param.langFilter).assertFalse();
      expect(param.minRating).assertEqual(4);
    });

    it('quickSearchSummary_describes_conditions', 0, () => {
      const rec: QuickSearch = {
        id: 1, category: 0x2, keyword: 'nico', language: '',
        advanceSearch: 3, minRating: 4, time: 0, saved: 1
      };
      expect(quickSearchSummary(rec)).assertEqual('排除 DOUJINSHI · title/tags · ★4+');
    });

    it('quickSearchSummary_empty_for_defaults', 0, () => {
      expect(quickSearchSummary(row('soutsa'))).assertEqual('');
    });

    it('quickSearch_round_trips_language', 0, () => {
      const rec: QuickSearch = {
        id: 1, category: 0, keyword: 'lang', language: 'chinese',
        advanceSearch: 0, minRating: -1, time: 0, saved: 1
      };
      expect(quickSearchToParam(rec).language).assertEqual('chinese');
      expect(quickSearchSummary(rec)).assertEqual('chinese');
    });

    it('quickSearchToParam_old_record_falls_back_to_defaults', 0, () => {
      const param = quickSearchToParam(row('soutsa'));
      expect(param.query).assertEqual('soutsa');
      expect(param.selectedBits !== undefined &&
        param.selectedBits.length).assertEqual(ALL_CATS.length);
      expect(param.scopes !== undefined && param.scopes.length).assertEqual(0);
      expect(param.langFilter).assertFalse();
      expect(param.minRating).assertEqual(-1);
    });

    it('quickSearch_round_trips_multi_condition_verbatim', 0, () => {
      // 保存的是 chips 拼出的**完整**串，恢复时原样发出：任何「按入口模式改写语法」的处理都会
      // 把第二个条件吞进第一个标签的值里（`char:"a$" big breasts` → `char:"a$" big breasts$"`）。
      const keyword: string = joinQueryText(['character:"sparkle$"', '-female:"big breasts$"'], '');
      expect(keyword).assertEqual('character:"sparkle$" -female:"big breasts$"');
      const rec: QuickSearch = {
        id: 1, category: 0, keyword: keyword, language: 'chinese',
        advanceSearch: 0, minRating: -1, time: 0, saved: 1
      };
      const param = quickSearchToParam(rec);
      expect(param.query).assertEqual(keyword);
      expect(splitQueryTokens(param.query).length).assertEqual(2);
      expect(param.language).assertEqual('chinese');
      // 手写的 qualifier（上传者 / 裸关键词）也不改写。
      expect(quickSearchToParam(row('uploader:"some one"')).query).assertEqual('uploader:"some one"');
      expect(quickSearchToParam(row('blue archive')).query).assertEqual('blue archive');
    });

    it('quickSearch_round_trips_language_and_rating', 0, () => {
      const rec: QuickSearch = {
        id: 1, category: 0, keyword: 'character:"sparkle$"', language: 'chinese',
        advanceSearch: 0, minRating: 4, time: 0, saved: 1
      };
      const param = quickSearchToParam(rec);
      expect(param.query).assertEqual('character:"sparkle$"');
      expect(param.language).assertEqual('chinese');
      expect(param.minRating).assertEqual(4);
    });

    // —— 搜索历史（与快搜同表，靠 `saved` 区分）——

    it('sameSearch_ignores_case_and_time', 0, () => {
      const a: QuickSearch = row('Female:"Big Breasts$"');
      const b: QuickSearch = row('female:"big breasts$"');
      b.id = 9;
      b.time = 1234;
      expect(sameSearch(a, b)).assertTrue();
    });

    it('sameSearch_separates_different_conditions', 0, () => {
      const a: QuickSearch = row('nico');
      const b: QuickSearch = row('nico');
      b.minRating = 4;
      expect(sameSearch(a, b)).assertFalse();
      const c: QuickSearch = row('nico');
      c.category = 0x2;
      expect(sameSearch(a, c)).assertFalse();
      const d: QuickSearch = row('nico');
      d.language = 'chinese';
      expect(sameSearch(a, d)).assertFalse();
    });

    it('historyIdsToPrune_keeps_newest', 0, () => {
      const rows: QuickSearch[] = [];
      for (let i = 0; i < 5; i++) {
        const r: QuickSearch = row(`k${i}`);
        r.id = i + 1;
        rows.push(r);
      }
      expect(historyIdsToPrune(rows, 3).length).assertEqual(2);
      expect(historyIdsToPrune(rows, 3)[0]).assertEqual(4);
      expect(historyIdsToPrune(rows, 10).length).assertEqual(0);
      expect(historyIdsToPrune(rows, 0).length).assertEqual(0);
    });
  });
}
