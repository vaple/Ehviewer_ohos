import { describe, it, expect } from '@ohos/hypium';
import { EhUrl, EhSite } from '../../main/ets/network/EhUrl';
import { fCatsMask, excludedFromSelected, encodeAdvance, decodeAdvance, DecodedAdvance, selectedFromExcluded, ALL_CATS, languageQueryOf, searchKindOf, exclusionQueryOf, qualifyTag, exactTagQuery, SearchFilters } from '../../main/ets/search/SearchQuery';
import { Filter } from '../../main/ets/model/Filter';

export default function searchQueryTest() {
  describe('SearchQuery', () => {
    it('search_basic_no_page', 0, () => {
      const url: string = EhUrl.search(EhSite.EX, 'naruto', 0);
      expect(url.includes('f_search=naruto')).assertTrue();
      expect(url.includes('page=')).assertFalse();
    });

    it('search_encodes_space_as_plus_and_page', 0, () => {
      const url: string = EhUrl.search(EhSite.EX, 'a b', 2);
      expect(url.includes('a+b')).assertTrue();
      expect(url.includes('page=2')).assertTrue();
    });

    it('search_empty_query_omits_f_search', 0, () => {
      const url: string = EhUrl.search(EhSite.EX, '  ', 0);
      expect(url.includes('f_search')).assertFalse();
    });

    it('search_f_cats', 0, () => {
      const url: string = EhUrl.search(EhSite.EX, 'x', 0, fCatsMask([0x2]));
      expect(url.includes('f_cats=2')).assertTrue();
    });

    it('search_uploader_and_tag_paths', 0, () => {
      expect(EhUrl.uploader(EhSite.EX, 'some one', 0))
        .assertEqual('https://exhentai.org/uploader/some+one/');
      expect(EhUrl.uploader(EhSite.EX, 'u', 3))
        .assertEqual('https://exhentai.org/uploader/u/3');
      expect(EhUrl.tag(EhSite.EX, 'artist:abc', 0))
        .assertEqual('https://exhentai.org/tag/artist%3Aabc/');
    });

    it('fCatsMask_or_semantics', 0, () => {
      expect(fCatsMask([])).assertEqual(0);
      expect(fCatsMask([0x2])).assertEqual(0x2);
      expect(fCatsMask([0x1, 0x4])).assertEqual(0x5);
    });

    it('search_f_cats_combo_exact_url', 0, () => {
      expect(EhUrl.search(EhSite.EX, 'x', 1, fCatsMask([0x2, 0x100])))
        .assertEqual('https://exhentai.org/?f_search=x&f_cats=258&page=1');
      expect(EhUrl.search(EhSite.E, 'x', 0, fCatsMask([])))
        .assertEqual('https://e-hentai.org/?f_search=x');
    });

    it('search_filters_scopes_exact_url', 0, () => {
      const f: SearchFilters = {
        inTitle: true, inTags: true, inDesc: false, inTorrents: false,
        language: false, minRating: -1,
        onlyTorrents: false, ignoreFilters: false, pageFrom: -1, pageTo: -1
      };
      expect(EhUrl.search(EhSite.EX, 'naruto', 0, 0, f))
        .assertEqual('https://exhentai.org/?f_search=naruto&advsearch=1&f_sname=on&f_stags=on');
    });

    it('search_filters_language_exact_url', 0, () => {
      const f: SearchFilters = {
        inTitle: false, inTags: false, inDesc: false, inTorrents: false,
        language: true, minRating: -1,
        onlyTorrents: false, ignoreFilters: false, pageFrom: -1, pageTo: -1
      };
      expect(EhUrl.search(EhSite.EX, 'naruto', 0, 0, f))
        .assertEqual('https://exhentai.org/?f_search=naruto&advsearch=1&f_sfl=on');
    });

    it('search_filters_min_rating_exact_url', 0, () => {
      const f: SearchFilters = {
        inTitle: false, inTags: false, inDesc: false, inTorrents: false,
        language: false, minRating: 4,
        onlyTorrents: false, ignoreFilters: false, pageFrom: -1, pageTo: -1
      };
      expect(EhUrl.search(EhSite.EX, 'naruto', 0, 0, f))
        .assertEqual('https://exhentai.org/?f_search=naruto&advsearch=1&f_sr=on&f_srdd=4');
    });

    it('search_filters_full_combo_exact_url', 0, () => {
      const f: SearchFilters = {
        inTitle: true, inTags: true, inDesc: true, inTorrents: true,
        language: true, minRating: 3,
        onlyTorrents: false, ignoreFilters: false, pageFrom: -1, pageTo: -1
      };
      expect(EhUrl.search(EhSite.EX, 'a b', 2, 0x4, f))
        .assertEqual('https://exhentai.org/?f_search=a+b&f_cats=4&advsearch=1' +
          '&f_sname=on&f_stags=on&f_sdesc=on&f_storr=on&f_sfl=on&f_sr=on&f_srdd=3&page=2');
    });

    it('search_filters_invalid_rating_ignored', 0, () => {
      const f: SearchFilters = {
        inTitle: false, inTags: false, inDesc: false, inTorrents: false,
        language: false, minRating: 7,
        onlyTorrents: false, ignoreFilters: false, pageFrom: -1, pageTo: -1
      };
      expect(EhUrl.search(EhSite.EX, 'naruto', 0, 0, f))
        .assertEqual('https://exhentai.org/?f_search=naruto');
    });

    it('search_filters_official_advanced_params', 0, () => {
      const f: SearchFilters = {
        inTitle: false, inTags: false, inDesc: false, inTorrents: false,
        language: false, minRating: -1,
        onlyTorrents: true, ignoreFilters: true, pageFrom: 100, pageTo: 200
      };
      expect(EhUrl.search(EhSite.EX, 'naruto', 0, 0, f))
        .assertEqual('https://exhentai.org/?f_search=naruto&advsearch=1' +
          '&f_sto=on&f_sp=on&f_spf=100&f_spt=200&f_sfl=on&f_sfu=on&f_sft=on');
    });

    it('search_filters_inactive_object_old_shape', 0, () => {
      const f: SearchFilters = {
        inTitle: false, inTags: false, inDesc: false, inTorrents: false,
        language: false, minRating: -1,
        onlyTorrents: false, ignoreFilters: false, pageFrom: -1, pageTo: -1
      };
      expect(EhUrl.search(EhSite.EX, 'naruto', 0, 0, f))
        .assertEqual('https://exhentai.org/?f_search=naruto');
    });

    it('excludedFromSelected_partial', 0, () => {
      const excluded: number[] = excludedFromSelected([0x2], [0x1, 0x2]);
      expect(excluded.length).assertEqual(1);
      expect(excluded[0]).assertEqual(0x1);
    });

    it('excludedFromSelected_empty_select_means_all', 0, () => {
      expect(excludedFromSelected([], [0x1, 0x2]).length).assertEqual(0);
    });

    it('excludedFromSelected_all_selected_means_none_excluded', 0, () => {
      expect(excludedFromSelected([0x1, 0x2], [0x1, 0x2]).length).assertEqual(0);
    });

    it('languageQueryOf_empty_or_single', 0, () => {
      expect(languageQueryOf('')).assertEqual('');
      expect(languageQueryOf('chinese')).assertEqual('language:chinese');
    });

    it('exclusionQueryOf_empty_single_multi', 0, () => {
      const on: Filter = { id: 1, mode: 0, text: 'loli', enable: true };
      const off: Filter = { id: 2, mode: 0, text: 'shota', enable: false };
      expect(exclusionQueryOf([], [])).assertEqual('');
      expect(exclusionQueryOf([off], [])).assertEqual('');
      expect(exclusionQueryOf([on], [])).assertEqual('-loli');
    });

    it('exclusionQueryOf_quotes_phrases_and_namespaces', 0, () => {
      const title: Filter = { id: 1, mode: 0, text: 'title:big breasts', enable: true };
      expect(exclusionQueryOf([title], [])).assertEqual('-title:"big breasts"');
      const up: Filter = { id: 2, mode: 0, text: 'uploader:John Doe', enable: true };
      expect(exclusionQueryOf([up], [])).assertEqual('-uploader:"John Doe"');
      const tag: Filter = { id: 3, mode: 0, text: 'parody:fairy tail', enable: true };
      expect(exclusionQueryOf([tag], [])).assertEqual('-parody:"fairy tail"');
    });

    it('exclusionQueryOf_ignores_and_caps_at_ten', 0, () => {
      const a: Filter = { id: 1, mode: 0, text: 'a', enable: true };
      const b: Filter = { id: 2, mode: 0, text: 'b', enable: true };
      expect(exclusionQueryOf([a, b], ['a'])).assertEqual('-b');
      const many: Filter[] = [];
      for (let i = 0; i < 12; i++) {
        many.push({ id: i, mode: 0, text: `w${i}`, enable: true });
      }
      const out: string = exclusionQueryOf(many, []);
      expect(out.split(' ').length).assertEqual(10);
    });

    it('qualifyTag_quotes_multiword_part', 0, () => {
      expect(qualifyTag('parody:fairy tail')).assertEqual('parody:"fairy tail"');
      expect(qualifyTag('loli')).assertEqual('loli');
      // 已包好的串不再包第二层（规则文本可能就是 exactTagQuery 产物）。
      expect(qualifyTag('parody:"fairy tail$"')).assertEqual('parody:"fairy tail$"');
    });

    it('exactTagQuery_quotes_and_anchors', 0, () => {
      // 含空格：引号并成一个词；`$` 锚整词（源 `wrapTagKeyword` 同形）。
      expect(exactTagQuery('parody:blue archive')).assertEqual('parody:"blue archive$"');
      // 单词标签同样带引号与锚（源做法对**所有**标签都加）。
      expect(exactTagQuery('artist:foo')).assertEqual('artist:"foo$"');
      // 排除前缀保留。
      expect(exactTagQuery('-parody:blue archive')).assertEqual('-parody:"blue archive$"');
    });

    it('exactTagQuery_is_idempotent', 0, () => {
      expect(exactTagQuery('parody:"blue archive$"')).assertEqual('parody:"blue archive$"');
      expect(exactTagQuery('parody:"blue archive"')).assertEqual('parody:"blue archive$"');
      expect(exactTagQuery('artist:foo$')).assertEqual('artist:"foo$"');
    });

    it('exactTagQuery_passes_through_bare_keyword', 0, () => {
      // 无命名空间不替用户猜。
      expect(exactTagQuery('blue archive')).assertEqual('blue archive');
      expect(exactTagQuery('  ')).assertEqual('');
    });

    it('searchKindOf_maps_mode_to_kind', 0, () => {
      expect(searchKindOf(0)).assertEqual('keyword');
      expect(searchKindOf(1)).assertEqual('uploader');
      expect(searchKindOf(2)).assertEqual('tag');
      expect(searchKindOf(9)).assertEqual('keyword');
    });

    it('encodeAdvance_roundtrip_scopes_and_lang', 0, () => {
      const mask: number = encodeAdvance(['title', 'tags'], true);
      const back: DecodedAdvance = decodeAdvance(mask);
      expect(back.scopes.length).assertEqual(2);
      expect(back.scopes[0]).assertEqual('title');
      expect(back.scopes[1]).assertEqual('tags');
      expect(back.langFilter).assertTrue();
    });

    it('encodeAdvance_empty_means_defaults', 0, () => {
      const back: DecodedAdvance = decodeAdvance(encodeAdvance([], false));
      expect(back.scopes.length).assertEqual(0);
      expect(back.langFilter).assertFalse();
    });

    it('selectedFromExcluded_partial_and_zero', 0, () => {
      const sel: number[] = selectedFromExcluded(0x1, [0x1, 0x2]);
      expect(sel.length).assertEqual(1);
      expect(sel[0]).assertEqual(0x2);
      expect(selectedFromExcluded(0, [0x1, 0x2]).length).assertEqual(2);
    });
  });
}
