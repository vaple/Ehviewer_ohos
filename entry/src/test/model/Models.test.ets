import { describe, it, expect } from '@ohos/hypium';
import { QuickSearch } from '../../main/ets/model/QuickSearch';
import { HistoryInfo } from '../../main/ets/model/HistoryInfo';

export default function modelsTest() {
  describe('Models', () => {
    it('quick_search_has_real_columns', 0, () => {
      const qs: QuickSearch = {
        id: 0, name: 'n', mode: 1, category: 2, keyword: 'k', language: '',
        advanceSearch: 0, minRating: 4, pageFrom: -1, pageTo: -1, time: 123
      };
      expect(qs.mode).assertEqual(1);
      expect(qs.category).assertEqual(2);
      expect(qs.minRating).assertEqual(4);
      expect(qs.pageFrom).assertEqual(-1);
      expect(qs.time).assertEqual(123);
    });

    it('history_info_extends_gallery_info', 0, () => {
      const h: HistoryInfo = {
        gid: 5, token: 't', title: 'T', titleJpn: '', thumb: 'u',
        category: 1, posted: 'p', uploader: 'up', rating: 4.5, simpleLanguage: 'EN',
        pages: 12, mode: 0, time: 9
      };
      expect(h.gid).assertEqual(5);
      expect(h.title).assertEqual('T');
      expect(h.mode).assertEqual(0);
      expect(h.rating).assertEqual(4.5);
      expect(h.pages).assertEqual(12);
    });
  });
}
