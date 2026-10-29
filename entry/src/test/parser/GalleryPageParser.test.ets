import { describe, it, expect } from '@ohos/hypium';
import { GalleryPageParser, GalleryPageResult } from '../../main/ets/parser/GalleryPageParser';
import { GALLERY_PAGE_HTML } from '../fixtures/galleryPage';

export default function galleryPageParserTest() {
  describe('GalleryPageParser', () => {
    it('parses_real_image_page', 0, () => {
      const r: GalleryPageResult | null = GalleryPageParser.parse(GALLERY_PAGE_HTML, 4253086, 1);
      expect(r !== null).assertTrue();
      expect(r?.imageUrl.startsWith('https://')).assertTrue();
      expect(r?.imageUrl.includes('.webp')).assertTrue();
      expect(r?.skipHathKey).assertEqual('28828-497763');
      expect(r?.nextPToken).assertEqual('a0113b5a19');
    });

    it('parses_original_image_link', 0, () => {
      const html: string =
        '<div id="i7"><a href="https://e-hentai.org/fullimg/4282230/1/cy64ur4aoar/_1.jpg">' +
        'Download original</a></div>';
      // 用真实图片页 fixture + 追加 original 链接，验证同一页能同时给出展示图与原图。
      const r: GalleryPageResult | null = GalleryPageParser.parse(GALLERY_PAGE_HTML + html, 4253086, 1);
      expect(r?.originalUrl).assertEqual('https://e-hentai.org/fullimg/4253086/1/okmfndqao2r/1.png');
    });

    it('missing_img_returns_null', 0, () => {
      expect(GalleryPageParser.parse('<html><body>nope</body></html>')).assertNull();
    });
  });
}
