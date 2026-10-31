import { describe, it, expect } from '@ohos/hypium';
import { DetailCache } from '../../main/ets/network/DetailCache';
import { EhSite } from '../../main/ets/network/EhUrl';
import { GalleryDetail } from '../../main/ets/model/GalleryDetail';

function detailOf(gid: number): GalleryDetail {
  return {
    gid, token: 't', title: 'x', titleJpn: '', category: 0, uploader: '', posted: '',
    rating: 0, ratingCount: 0, pages: 1, thumb: '', tagGroups: [], previewTokens: [],
    previews: [], apiUid: -1, apiKey: '', comments: [], isFavorited: false, favoriteName: ''
  };
}

export default function detailCacheTest() {
  describe('DetailCache', () => {
    it('miss_returns_null', 0, () => {
      const c: DetailCache = new DetailCache(25, 180000, () => 0);
      expect(c.get(EhSite.E, 1, 0) === null).assertTrue();
    });

    it('hit_returns_equal_detail', 0, () => {
      const c: DetailCache = new DetailCache(25, 180000, () => 0);
      const d: GalleryDetail = detailOf(1);
      c.put(EhSite.E, 1, 0, d);
      const got: GalleryDetail | null = c.get(EhSite.E, 1, 0);
      expect(got === null).assertFalse();
      if (got !== null) {
        // 命中返回的是副本（`get_returns_independent_copy` 锁住这点），所以断言内容而不是引用。
        expect(got.gid).assertEqual(d.gid);
        expect(got.token).assertEqual(d.token);
        expect(got.title).assertEqual(d.title);
      }
      expect(c.size()).assertEqual(1);
    });

    it('get_returns_independent_copy', 0, () => {
      const c: DetailCache = new DetailCache(25, 180000, () => 0);
      c.put(EhSite.E, 1, 0, detailOf(1));
      const a: GalleryDetail | null = c.get(EhSite.E, 1, 0);
      expect(a === null).assertFalse();
      if (a !== null) {
        a.title = 'mutated';
        a.previewTokens.push('extra');
      }
      const b: GalleryDetail | null = c.get(EhSite.E, 1, 0);
      expect(b === null).assertFalse();
      if (b !== null) {
        expect(b.title).assertEqual('x');
        expect(b.previewTokens.length).assertEqual(0);
      }
    });

    it('key_isolates_site_and_thumb_size', 0, () => {
      const c: DetailCache = new DetailCache(25, 180000, () => 0);
      c.put(EhSite.E, 1, 0, detailOf(1));
      expect(c.get(EhSite.EX, 1, 0) === null).assertTrue();
      expect(c.get(EhSite.E, 1, 2) === null).assertTrue();
    });

    it('expires_after_ttl', 0, () => {
      let now: number = 0;
      const c: DetailCache = new DetailCache(25, 1000, () => now);
      c.put(EhSite.E, 1, 0, detailOf(1));
      now = 1001;
      expect(c.get(EhSite.E, 1, 0) === null).assertTrue();
      expect(c.size()).assertEqual(0);
    });

    it('evicts_least_recently_used', 0, () => {
      const c: DetailCache = new DetailCache(2, 180000, () => 0);
      c.put(EhSite.E, 1, 0, detailOf(1));
      c.put(EhSite.E, 2, 0, detailOf(2));
      c.get(EhSite.E, 1, 0);
      c.put(EhSite.E, 3, 0, detailOf(3));
      expect(c.get(EhSite.E, 1, 0) === null).assertFalse();
      expect(c.get(EhSite.E, 2, 0) === null).assertTrue();
      expect(c.size()).assertEqual(2);
    });

    it('drop_does_not_touch_shorter_gid_prefix', 0, () => {
      // key 用尾冒号分界：gid 1 的前缀 "0:1:" 不能命中 gid 10 的 "0:10:0"。
      const c: DetailCache = new DetailCache(25, 180000, () => 0);
      c.put(EhSite.E, 1, 0, detailOf(1));
      c.put(EhSite.E, 10, 0, detailOf(10));
      c.drop(EhSite.E, 1);
      expect(c.get(EhSite.E, 1, 0) === null).assertTrue();
      expect(c.get(EhSite.E, 10, 0) === null).assertFalse();
    });

    it('clear_removes_everything', 0, () => {
      const c: DetailCache = new DetailCache(25, 180000, () => 0);
      c.put(EhSite.E, 1, 0, detailOf(1));
      c.put(EhSite.EX, 2, 2, detailOf(2));
      c.clear();
      expect(c.size()).assertEqual(0);
      expect(c.get(EhSite.E, 1, 0) === null).assertTrue();
    });

    it('zero_ttl_disables_cache', 0, () => {
      const c: DetailCache = new DetailCache(25, 0, () => 0);
      c.put(EhSite.E, 1, 0, detailOf(1));
      expect(c.get(EhSite.E, 1, 0) === null).assertTrue();
      expect(c.size()).assertEqual(0);
    });

    it('drop_removes_all_thumb_sizes', 0, () => {
      const c: DetailCache = new DetailCache(25, 180000, () => 0);
      c.put(EhSite.E, 1, 0, detailOf(1));
      c.put(EhSite.E, 1, 2, detailOf(1));
      c.put(EhSite.E, 2, 0, detailOf(2));
      c.drop(EhSite.E, 1);
      expect(c.get(EhSite.E, 1, 0) === null).assertTrue();
      expect(c.get(EhSite.E, 1, 2) === null).assertTrue();
      expect(c.get(EhSite.E, 2, 0) === null).assertFalse();
    });
  });
}
