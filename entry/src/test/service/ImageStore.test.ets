import { describe, it, expect } from '@ohos/hypium';
import { ImageStore } from '../../main/ets/service/ImageStore';

/** H@H 直链前缀（真实 fixture 的形态，见 `entry/src/test/fixtures/galleryPage.ts`）。 */
const HATH_PREFIX: string =
  'https://cahxbkl.qzgpkqvnejff.hath.network:34680/h/' +
  'f3c6176e873611c79363cc950a4808152307abb2-99796-1216-832-wbp/keystamp=';

export default function imageStoreTest() {
  describe('ImageStore.cacheKey', () => {
    it('dropsRotatingKeystamp', 0, () => {
      const first: string = `${HATH_PREFIX}1791947400-88572222f4;fileindex=271561558;xres=1280/1.webp`;
      const second: string = `${HATH_PREFIX}1791999999-deadbeef00;fileindex=271561558;xres=1280/1.webp`;
      // 稳定段 = `/h/<hash>`，签名（keystamp）不参与。
      expect(ImageStore.stableKeyOf(first))
        .assertEqual('f3c6176e873611c79363cc950a4808152307abb2-99796-1216-832-wbp');
      // 两次加载签名不同 → 文件名必须相同（否则每次都 miss）。
      expect(ImageStore.nameOf(first)).assertEqual(ImageStore.nameOf(second));
    });

    it('keepsExtensionFromUrl', 0, () => {
      const url: string = `${HATH_PREFIX}1791947400-88572222f4;fileindex=1;xres=1280/1.webp`;
      expect(ImageStore.nameOf(url).endsWith('.webp')).assertTrue();
    });

    it('stripsQueryForPlainUrls', 0, () => {
      // 缩略图等没有 `/h/` 的地址：去掉 query（有些 CDN 会追加版本参数）。
      expect(ImageStore.stableKeyOf('https://ehgt.org/w/02/715/61838-cd63xded.webp?v=2'))
        .assertEqual('https://ehgt.org/w/02/715/61838-cd63xded.webp');
    });
  });
}
