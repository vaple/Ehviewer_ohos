import { describe, it, expect } from '@ohos/hypium';
import { hasSavedKeyword, quickSearchToParam, quickSearchSummary } from '../../main/ets/search/QuickSearchQuery';
import { QuickSearch } from '../../main/ets/model/QuickSearch';
import { ALL_CATS } from '../../main/ets/search/SearchQuery';

function row(keyword: string): QuickSearch {
  return {
    id: 1, name: keyword, mode: 0, category: 0, keyword: keyword, language: '',
    advanceSearch: 0, minRating: -1, pageFrom: -1, pageTo: -1, time: 0
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
        id: 1, name: 'nico', mode: 0, category: 0x2, keyword: 'nico', language: '',
        advanceSearch: 3, minRating: 4, pageFrom: -1, pageTo: -1, time: 0
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
        id: 1, name: 'nico', mode: 0, category: 0x2, keyword: 'nico', language: '',
        advanceSearch: 3, minRating: 4, pageFrom: -1, pageTo: -1, time: 0
      };
      expect(quickSearchSummary(rec)).assertEqual('排除 DOUJINSHI · title/tags · ★4+');
    });

    it('quickSearchSummary_empty_for_defaults', 0, () => {
      expect(quickSearchSummary(row('soutsa'))).assertEqual('');
    });

    it('quickSearch_round_trips_language', 0, () => {
      const rec: QuickSearch = {
        id: 1, name: 'lang', mode: 0, category: 0, keyword: 'lang', language: 'chinese',
        advanceSearch: 0, minRating: -1, pageFrom: -1, pageTo: -1, time: 0
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

    it('quickSearchToParam_tag_mode_writes_exact_syntax', 0, () => {
      // 修复前存的裸串（mode=2）再运行必须是 `namespace:"tag$"`：裸串会被搜索框拆成两个词。
      const legacy: QuickSearch = {
        id: 1, name: '标签', mode: 2, category: 0, keyword: 'parody:blue archive', language: '',
        advanceSearch: 0, minRating: -1, pageFrom: -1, pageTo: -1, time: 0
      };
      expect(quickSearchToParam(legacy).kind).assertEqual('tag');
      expect(quickSearchToParam(legacy).query).assertEqual('parody:"blue archive$"');
      // 已正规化的记录幂等。
      const modern: QuickSearch = {
        id: 2, name: '标签', mode: 2, category: 0, keyword: 'parody:"blue archive$"', language: '',
        advanceSearch: 0, minRating: -1, pageFrom: -1, pageTo: -1, time: 0
      };
      expect(quickSearchToParam(modern).query).assertEqual('parody:"blue archive$"');
      // keyword 态是用户自由表达式，不改写。
      expect(quickSearchToParam(row('blue archive')).query).assertEqual('blue archive');
    });
  });
}
