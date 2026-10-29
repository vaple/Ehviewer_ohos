import { describe, it, expect } from '@ohos/hypium';
import { GalleryRowItem, galleryGeometryId, rowLine1, rowLine2, thumbPending, toDetailPreview } from '../../main/ets/ui/GalleryRow';
import { DetailPreview } from '../../main/ets/model/DetailParam';
import { catLabel } from '../../main/ets/ui/CategoryStyle';
import {
  CATEGORY_MISC, CATEGORY_DOUJINSHI, CATEGORY_MANGA, CATEGORY_ARTIST_CG, CATEGORY_GAME_CG,
  CATEGORY_IMAGE_SET, CATEGORY_COSPLAY, CATEGORY_ASIAN_PORN, CATEGORY_NON_H, CATEGORY_WESTERN,
  CATEGORY_UNKNOWN
} from '../../main/ets/parser/ParserUtils';

export default function galleryRowTest() {
  describe('GalleryRow', () => {
    it('thumb_pending_when_remote_without_local', 0, () => {
      const item: GalleryRowItem = new GalleryRowItem();
      item.thumbUrl = 'https://ehgt.org/a/b/c.jpg';
      expect(thumbPending(item)).assertTrue();
    });

    it('thumb_not_pending_without_remote', 0, () => {
      expect(thumbPending(new GalleryRowItem())).assertFalse();
    });

    it('thumb_not_pending_when_cached', 0, () => {
      const item: GalleryRowItem = new GalleryRowItem();
      item.thumbUrl = 'https://ehgt.org/a/b/c.jpg';
      item.thumb = 'file://com.vaple.ehviewer/abc.jpg';
      expect(thumbPending(item)).assertFalse();
    });

    it('catLabel_uses_source_english_names', 0, () => {
      expect(catLabel(CATEGORY_MISC)).assertEqual('MISC');
      expect(catLabel(CATEGORY_DOUJINSHI)).assertEqual('DOUJINSHI');
      expect(catLabel(CATEGORY_MANGA)).assertEqual('MANGA');
      expect(catLabel(CATEGORY_ARTIST_CG)).assertEqual('ARTIST CG');
      expect(catLabel(CATEGORY_GAME_CG)).assertEqual('GAME CG');
      expect(catLabel(CATEGORY_IMAGE_SET)).assertEqual('IMAGE SET');
      expect(catLabel(CATEGORY_COSPLAY)).assertEqual('COSPLAY');
      expect(catLabel(CATEGORY_ASIAN_PORN)).assertEqual('ASIAN PORN');
      expect(catLabel(CATEGORY_NON_H)).assertEqual('NON-H');
      expect(catLabel(CATEGORY_WESTERN)).assertEqual('WESTERN');
    });

    it('catLabel_unknown_falls_back', 0, () => {
      expect(catLabel(CATEGORY_UNKNOWN)).assertEqual('UNKNOWN');
      expect(catLabel(0)).assertEqual('UNKNOWN');
    });

    it('rowLine1_joins_rating_lang_pages', 0, () => {
      const item: GalleryRowItem = new GalleryRowItem();
      item.rating = 4.5;
      item.simpleLanguage = 'ZH';
      item.pages = 121;
      expect(rowLine1(item)).assertEqual('★4.5 · ZH · 121P');
    });

    it('rowLine1_skips_empty_and_zero_pages', 0, () => {
      const item: GalleryRowItem = new GalleryRowItem();
      item.uploader = 'someone';
      expect(rowLine1(item)).assertEqual('');
      item.rating = 3;
      item.pages = 0;
      expect(rowLine1(item)).assertEqual('★3');
    });

    it('rowLine2_joins_uploader_posted', 0, () => {
      const item: GalleryRowItem = new GalleryRowItem();
      item.uploader = 'someone';
      item.posted = '2026-10-14';
      expect(rowLine2(item)).assertEqual('someone · 2026-10-14');
      expect(rowLine2(new GalleryRowItem())).assertEqual('');
    });

    it('rowInfo_migrated_to_two_lines', 0, () => {
      const item: GalleryRowItem = new GalleryRowItem();
      item.rating = 4.5;
      item.posted = '2026-10-14';
      item.simpleLanguage = 'ZH';
      item.uploader = 'someone';
      expect(rowLine1(item)).assertEqual('★4.5 · ZH');
      expect(rowLine2(item)).assertEqual('someone · 2026-10-14');
    });

    it('detailPreview_carries_list_snapshot', 0, () => {
      const item: GalleryRowItem = new GalleryRowItem();
      item.gid = 123;
      item.token = 'abc';
      item.title = 'A title';
      item.category = CATEGORY_MANGA;
      item.uploader = 'someone';
      item.rating = 4.5;
      item.pages = 88;
      item.thumbUrl = 'https://ehgt.org/a.jpg';
      item.thumb = 'file://com.vaple.ehviewer/a.jpg';
      const preview: DetailPreview = toDetailPreview(item);
      expect(preview.title).assertEqual('A title');
      expect(preview.category).assertEqual(CATEGORY_MANGA);
      expect(preview.uploader).assertEqual('someone');
      expect(preview.rating).assertEqual(4.5);
      expect(preview.pages).assertEqual(88);
      expect(preview.thumb).assertEqual('file://com.vaple.ehviewer/a.jpg');
      expect(preview.thumbUrl).assertEqual('https://ehgt.org/a.jpg');
    });

    it('detailPreview_keeps_unknown_category', 0, () => {
      const preview: DetailPreview = toDetailPreview(new GalleryRowItem());
      expect(preview.category).assertEqual(CATEGORY_UNKNOWN);
      expect(preview.pages).assertEqual(0);
      expect(preview.thumb).assertEqual('');
    });

    it('geometry_id_is_stable_per_gid', 0, () => {
      expect(galleryGeometryId(123)).assertEqual('gallery-123');
      expect(galleryGeometryId(456)).assertEqual('gallery-456');
    });
  });
}
