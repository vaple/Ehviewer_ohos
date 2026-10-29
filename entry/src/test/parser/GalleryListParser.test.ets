import { describe, it, expect } from '@ohos/hypium';
import { GalleryListParser } from '../../main/ets/parser/GalleryListParser';
import { GalleryInfo } from '../../main/ets/model/GalleryInfo';
import { CATEGORY_MISC } from '../../main/ets/parser/ParserUtils';
import { GALLERY_LIST_HTML } from '../fixtures/galleryListPage';

export default function galleryListParserTest() {
  describe('GalleryListParser', () => {
    it('parses_real_home_fixture', 0, () => {
      const list: GalleryInfo[] = GalleryListParser.parse(GALLERY_LIST_HTML);
      expect(list.length > 0).assertTrue();

      const found: GalleryInfo[] = list.filter((g: GalleryInfo) => g.gid === 4253086);
      expect(found.length).assertEqual(1);
      expect(found[0].token).assertEqual('3e5da257d9');
      expect(found[0].title.length > 0).assertTrue();
      expect(found[0].category).assertEqual(CATEGORY_MISC);
      expect(found[0].thumb.length > 0).assertTrue();
      expect(found[0].uploader).assertEqual('Joze julio');
      expect(found[0].posted).assertEqual('2026-10-14 00:02');
      expect(found[0].rating).assertEqual(2.5);
    });

    it('parses_pages_from_fixture', 0, () => {
      const list: GalleryInfo[] = GalleryListParser.parse(GALLERY_LIST_HTML);
      const found: GalleryInfo[] = list.filter((g: GalleryInfo) => g.gid === 4253088);
      expect(found.length).assertEqual(1);
      expect(found[0].pages).assertEqual(121);
    });

    it('parses_pages_missing_as_zero', 0, () => {
      const html: string =
        '<table class="itg"><tr><td class="gl3c glname">' +
        '<a href="https://e-hentai.org/g/1/abcdef0123/"><div class="glink">T</div></a></td></tr></table>';
      const list: GalleryInfo[] = GalleryListParser.parse(html);
      expect(list.length).assertEqual(1);
      expect(list[0].pages).assertEqual(0);
    });
    it('next_page_from_page_param', 0, () => {
      // 根列表页用 `next=` 游标（非页码）→ -1
      expect(GalleryListParser.parseNextPage(GALLERY_LIST_HTML)).assertEqual(-1);
      // 搜索/标签页用 `page=` 页码
      expect(GalleryListParser.parseNextPage('<a href="https://e-hentai.org/?page=2">Next</a>')).assertEqual(2);
      expect(GalleryListParser.parseNextPage('<div></div>')).assertEqual(-1);
    });

    it('ex_thumb_rewritten_to_ehgt', 0, () => {
      const html: string =
        '<table class="itg"><tr><td class="gl3c glname">' +
        '<a href="https://exhentai.org/g/1/abcdef0123/"><div class="glink">T</div></a></td>' +
        '<td class="gl2c"><img data-src="https://exhentai.org/t/31/7a/317a1a254cd9c3269e71b2aa2671fe8d28c91097-260198-640-480-png_250.jpg"/></td></tr></table>';
      const list: GalleryInfo[] = GalleryListParser.parse(html);
      expect(list.length).assertEqual(1);
      expect(list[0].thumb)
        .assertEqual('https://ehgt.org/31/7a/317a1a254cd9c3269e71b2aa2671fe8d28c91097-260198-640-480-png_250.jpg');
    });
    it('parses_compact_popular_row', 0, () => {
      const html: string =
        '<table class="itg gltc"><tr><th></th><th>Published</th><th>Title</th></tr>' +
        '<tr><td class="gl1c glcat"><div class="cn ct1">Misc</div></td>' +
        '<td class="gl2c"><div class="glthumb"><div>' +
        '<img src="https://s.exhentai.org/w/02/729/11397-80l5migp.webp"/>' +
        '</div><div><div><div class="cn ct1">Misc</div>' +
        '<div id="postedpop_4266551">2026-10-19 11:41</div></div>' +
        '<div><div class="ir" style="background-position:-16px -1px;opacity:1"></div>' +
        '<div>113 pages</div></div></div></div>' +
        '<div><div id="posted_4266551">2026-10-19 11:41</div></div></td>' +
        '<td class="gl3c glname">' +
        '<a href="https://exhentai.org/g/4266551/757a65f399/">' +
        '<div class="glink">popular title</div></a></td>' +
        '<td class="gl4c glhide"><div>' +
        '<a href="https://exhentai.org/uploader/e23s567">e23s567</a>' +
        '</div><div>113 pages</div></td></tr></table>';
      const list: GalleryInfo[] = GalleryListParser.parse(html);
      expect(list.length).assertEqual(1);
      expect(list[0].gid).assertEqual(4266551);
      expect(list[0].token).assertEqual('757a65f399');
      expect(list[0].title).assertEqual('popular title');
      expect(list[0].uploader).assertEqual('e23s567');
      expect(list[0].pages).assertEqual(113);
      expect(list[0].posted).assertEqual('2026-10-19 11:41');
    });
    it('parses_thumbnail_grid_tiles', 0, () => {
      const html: string =
        '<div class="itg gld"><div class="gl1t">' +
        '<a href="https://e-hentai.org/g/4264951/e661dba17d/">' +
        '<div class="gl4t glname glink">grid title</div></a>' +
        '<div class="gl3t"><a href="https://e-hentai.org/g/4264951/e661dba17d/">' +
        '<img src="https://ehgt.org/w/02/727/33217-l353ogfc.webp"/>' +
        '</a></div><div class="gl5t"><div><div class="cs ct1">Misc</div>' +
        '<div id="posted_4264951">2026-10-18 19:47</div></div>' +
        '<div><div class="ir" style="background-position:-32px -21px;opacity:1"></div>' +
        '<div>45 pages</div></div></div></div></div>';
      const list: GalleryInfo[] = GalleryListParser.parse(html);
      expect(list.length).assertEqual(1);
      expect(list[0].gid).assertEqual(4264951);
      expect(list[0].token).assertEqual('e661dba17d');
      expect(list[0].title).assertEqual('grid title');
      expect(list[0].category).assertEqual(CATEGORY_MISC);
      expect(list[0].thumb).assertEqual('https://ehgt.org/w/02/727/33217-l353ogfc.webp');
      expect(list[0].posted).assertEqual('2026-10-18 19:47');
      expect(list[0].pages).assertEqual(45);
      expect(list[0].rating).assertEqual(2.5);
    });

    it('title_falls_back_to_row_glink_when_first_anchor_is_cover', 0, () => {
      // 缩略图模式：第一个详情链接是封面 `<a><img/></a>`（无文字），标题在另一个 `.glink` 里。
      const html: string =
        '<div class="itg gld"><div class="gl1t">' +
        '<a href="https://e-hentai.org/g/9/abcdef0123/"><img src="https://ehgt.org/x.jpg"/></a>' +
        '<div class="gl4t"><a href="https://e-hentai.org/g/9/abcdef0123/">' +
        '<div class="glink">grid title</div></a></div>' +
        '</div></div>';
      const list: GalleryInfo[] = GalleryListParser.parse(html);
      expect(list.length).assertEqual(1);
      expect(list[0].title).assertEqual('grid title');
    });

    it('language_tag_inside_detail_anchor', 0, () => {      const html: string =
        '<table class="itg"><tr><td class="gl3c glname">' +
        '<a href="https://exhentai.org/g/1/abcdef0123/">' +
        '<div class="glink">[Chinese] title</div>' +
        '<div><div class="gt" title="language:chinese">chinese</div></div></a></td></tr></table>';
      const list: GalleryInfo[] = GalleryListParser.parse(html);
      expect(list.length).assertEqual(1);
      expect(list[0].simpleLanguage).assertEqual('ZH');
    });

    it('language_tag_outside_detail_anchor_same_row', 0, () => {
      // 缩略图/紧凑布局里 `.gt` 可能被移出详情 `<a>`：整行取标签仍能命中。
      const html: string =
        '<div class="itg gld"><div class="gl1t">' +
        '<a href="https://e-hentai.org/g/2/abcdef0123/">' +
        '<div class="gl4t glname glink">grid title</div></a>' +
        '<div class="gt" title="language:chinese">chinese</div>' +
        '<div class="gl5t"><div class="cs ct1">Misc</div><div>45 pages</div></div>' +
        '</div></div>';
      const list: GalleryInfo[] = GalleryListParser.parse(html);
      expect(list.length).assertEqual(1);
      expect(list[0].simpleLanguage).assertEqual('ZH');
    });

    it('no_language_tag_means_empty_not_guessed', 0, () => {
      // 标题里有 [Chinese] 但站点没给 language 标签 → 不显示（不做标题兜底）。
      const html: string =
        '<table class="itg"><tr><td class="gl3c glname">' +
        '<a href="https://exhentai.org/g/3/abcdef0123/">' +
        '<div class="glink">[Chinese] title</div>' +
        '<div><div class="gt" title="parody:foo">foo</div></div></a></td></tr></table>';
      const list: GalleryInfo[] = GalleryListParser.parse(html);
      expect(list.length).assertEqual(1);
      expect(list[0].simpleLanguage).assertEqual('');
    });
  });
}
