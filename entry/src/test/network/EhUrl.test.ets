import { describe, it, expect } from '@ohos/hypium';
import { EhUrl, EhSite } from '../../main/ets/network/EhUrl';

export default function ehUrlTest() {
  describe('EhUrl', () => {
    it('host_by_site', 0, () => {
      expect(EhUrl.host(EhSite.E)).assertEqual('https://e-hentai.org/');
      expect(EhUrl.host(EhSite.EX)).assertEqual('https://exhentai.org/');
    });

    it('home_and_api', 0, () => {
      expect(EhUrl.home(EhSite.E)).assertEqual('https://e-hentai.org/home.php');
      expect(EhUrl.frontPage(EhSite.E)).assertEqual('https://e-hentai.org/');
      expect(EhUrl.api(EhSite.EX)).assertEqual('https://exhentai.org/api.php');
    });

    it('gallery_detail_url', 0, () => {
      expect(EhUrl.galleryDetail(EhSite.E, 123456, 'abcdef')).assertEqual('https://e-hentai.org/g/123456/abcdef/');
      expect(EhUrl.galleryDetail(EhSite.EX, 7, 'tok')).assertEqual('https://exhentai.org/g/7/tok/');
    });

    it('gallery_detail_chunk_url', 0, () => {
      expect(EhUrl.galleryDetailChunk(EhSite.E, 123456, 'abcdef', 0))
        .assertEqual('https://e-hentai.org/g/123456/abcdef/');
      expect(EhUrl.galleryDetailChunk(EhSite.EX, 7, 'tok', 2))
        .assertEqual('https://exhentai.org/g/7/tok/?p=2');
    });

    it('gallery_page_url_and_skip_hath_key', 0, () => {
      expect(EhUrl.galleryPage(EhSite.EX, 123456, 3, 'ptok')).assertEqual('https://exhentai.org/s/ptok/123456-3');
      expect(EhUrl.galleryPage(EhSite.EX, 123456, 3, 'ptok', 'KEY'))
        .assertEqual('https://exhentai.org/s/ptok/123456-3?nl=KEY');
    });

    it('fixed_preview_thumb_rewrites_to_ehgt', 0, () => {
      const origin: string =
        'https://exhentai.org/t/31/7a/317a1a254cd9c3269e71b2aa2671fe8d28c91097-260198-640-480-png_250.jpg';
      expect(EhUrl.fixedPreviewThumb(origin))
        .assertEqual('https://ehgt.org/31/7a/317a1a254cd9c3269e71b2aa2671fe8d28c91097-260198-640-480-png_250.jpg');
    });

    it('fixed_preview_thumb_keeps_origin_when_not_matching', 0, () => {
      const origin: string = 'https://example.com/a/b/notmatching.jpg';
      expect(EhUrl.fixedPreviewThumb(origin)).assertEqual(origin);
    });

    it('watched_url', 0, () => {
      expect(EhUrl.watched(EhSite.EX, 0)).assertEqual('https://exhentai.org/watched');
      expect(EhUrl.watched(EhSite.EX, 2)).assertEqual('https://exhentai.org/watched?page=2');
      expect(EhUrl.watched(EhSite.E, 0)).assertEqual('https://e-hentai.org/watched');
    });

    it('popular_url', 0, () => {
      expect(EhUrl.popular(EhSite.EX)).assertEqual('https://exhentai.org/popular');
      expect(EhUrl.popular(EhSite.E)).assertEqual('https://e-hentai.org/popular');
    });

    it('toplist_url_ranges', 0, () => {
      expect(EhUrl.toplist('yesterday', 0))
        .assertEqual('https://e-hentai.org/toplist.php?tl=15');
      expect(EhUrl.toplist('month', 0))
        .assertEqual('https://e-hentai.org/toplist.php?tl=13');
      expect(EhUrl.toplist('year', 0))
        .assertEqual('https://e-hentai.org/toplist.php?tl=12');
      expect(EhUrl.toplist('all', 0))
        .assertEqual('https://e-hentai.org/toplist.php?tl=11');
      expect(EhUrl.toplist('all', 1))
        .assertEqual('https://e-hentai.org/toplist.php?tl=11&p=1');
    });

    it('favorites_url', 0, () => {
      expect(EhUrl.favorites(EhSite.EX, -1, '', 0))
        .assertEqual('https://exhentai.org/favorites.php');
      expect(EhUrl.favorites(EhSite.EX, 0, '', 0))
        .assertEqual('https://exhentai.org/favorites.php?favcat=0');
      expect(EhUrl.favorites(EhSite.EX, -1, 'abc', 0))
        .assertEqual('https://exhentai.org/favorites.php?f_search=abc&sn=on&st=on&sf=on');
      expect(EhUrl.favorites(EhSite.EX, 2, 'a b', 3))
        .assertEqual('https://exhentai.org/favorites.php?favcat=2&f_search=a+b&sn=on&st=on&sf=on&page=3');
    });

    it('addfav_url', 0, () => {
      expect(EhUrl.addFav(EhSite.EX, 1, 't'))
        .assertEqual('https://exhentai.org/gallerypopups.php?gid=1&t=t&act=addfav');
    });

    it('favorder_url', 0, () => {
      expect(EhUrl.favOrderUrl(EhSite.EX, 'f', -1, '', 0))
        .assertEqual('https://exhentai.org/favorites.php?inline_set=fs_f');
      expect(EhUrl.favOrderUrl(EhSite.EX, 'p', 2, 'ab', 1))
        .assertEqual('https://exhentai.org/favorites.php?favcat=2&f_search=ab&sn=on&st=on&sf=on&page=1&inline_set=fs_p');
    });

    it('uconfig_url_by_site', 0, () => {
      expect(EhUrl.uconfig(EhSite.E)).assertEqual('https://e-hentai.org/uconfig.php');
      expect(EhUrl.uconfig(EhSite.EX)).assertEqual('https://exhentai.org/uconfig.php');
    });

    it('mytags_url_by_site', 0, () => {
      expect(EhUrl.myTags(EhSite.E)).assertEqual('https://e-hentai.org/mytags');
      expect(EhUrl.myTags(EhSite.EX)).assertEqual('https://exhentai.org/mytags');
    });

    it('thumb_resolution_rewrites_suffix', 0, () => {
      expect(EhUrl.thumbResolution('https://ehgt.org/31/7a/img_250.jpg', 2))
        .assertEqual('https://ehgt.org/31/7a/img_300.jpg');
      expect(EhUrl.thumbResolution('https://ehgt.org/31/7a/img_300.jpg', 1))
        .assertEqual('https://ehgt.org/31/7a/img_250.jpg');
    });

    it('thumb_resolution_zero_and_invalid_keep_origin', 0, () => {
      const url: string = 'https://ehgt.org/31/7a/img_250.jpg';
      expect(EhUrl.thumbResolution(url, 0)).assertEqual(url);
      expect(EhUrl.thumbResolution(url, 9)).assertEqual(url);
      expect(EhUrl.thumbResolution('https://ehgt.org/31/7a/img.jpg', 2))
        .assertEqual('https://ehgt.org/31/7a/img.jpg');
    });
  });
}
