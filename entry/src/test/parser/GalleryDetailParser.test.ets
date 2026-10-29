import { describe, it, expect } from '@ohos/hypium';
import { GalleryDetailParser, tagQueryOf } from '../../main/ets/parser/GalleryDetailParser';
import { PreviewItem } from '../../main/ets/model/PreviewItem';
import { GalleryDetail } from '../../main/ets/model/GalleryDetail';
import { TagGroup } from '../../main/ets/model/TagGroup';
import { CATEGORY_MISC } from '../../main/ets/parser/ParserUtils';
import { GALLERY_DETAIL_HTML } from '../fixtures/galleryDetailPage';

export default function galleryDetailParserTest() {
  describe('GalleryDetailParser', () => {
    it('parses_real_detail_fixture', 0, () => {
      const d: GalleryDetail | null = GalleryDetailParser.parse(GALLERY_DETAIL_HTML, 4253086);
      expect(d !== null).assertTrue();
      expect(d?.gid).assertEqual(4253086);
      expect(d?.title).assertEqual('[ValenAiart12] Nico [AI Generated]');
      expect(d?.titleJpn).assertEqual('');
      expect(d?.category).assertEqual(CATEGORY_MISC);
      expect(d?.uploader).assertEqual('Joze julio');
      expect(d?.rating).assertEqual(2.61);
      expect(d?.ratingCount).assertEqual(9);
      expect(d?.pages).assertEqual(52);
      expect((d?.tagGroups.length ?? 0) > 0).assertTrue();
      expect((d?.previewTokens.length ?? 0) > 0).assertTrue();
      expect(d?.previewTokens[0]).assertEqual('bb9f06e264');
      expect(d?.previewTokens[1]).assertEqual('a0113b5a19');
      expect(d?.apiUid).assertEqual(-1);
      expect(d?.apiKey).assertEqual('341ba9d027ae772a1d4c');
      expect(d?.comments.length).assertEqual(0);
      expect(d?.thumb).assertEqual('https://ehgt.org/w/02/715/61558-qd609ha1.webp');
    });

    it('last_reason_reports_empty_body_and_missing_gn', 0, () => {
      GalleryDetailParser.parse('', 1, '');
      expect(GalleryDetailParser.lastReason()).assertEqual('empty body');
      GalleryDetailParser.parse('<html><body><h1>maintenance</h1></body></html>', 1, '');
      expect(GalleryDetailParser.lastReason()).assertEqual('no #gn');
    });

    it('parses_tag_groups_from_fixture', 0, () => {
      const d: GalleryDetail | null = GalleryDetailParser.parse(GALLERY_DETAIL_HTML, 4253086);
      expect(d !== null).assertTrue();
      const groups: TagGroup[] = d?.tagGroups ?? [];
      expect(groups.length).assertEqual(3);
      expect(groups[0].namespace).assertEqual('parody');
      expect(groups[0].tags.length).assertEqual(1);
      expect(groups[0].tags[0]).assertEqual('love live');
      expect(groups[1].namespace).assertEqual('character');
      expect(groups[1].tags.length).assertEqual(1);
      expect(groups[1].tags[0]).assertEqual('nico yazawa');
      expect(groups[2].namespace).assertEqual('other');
      expect(groups[2].tags.length).assertEqual(1);
      expect(groups[2].tags[0]).assertEqual('ai generated');
    });

    it('parseTagGroups_skips_empty_groups', 0, () => {
      const html: string = '<div id="taglist"><table>' +
        '<tr><td class="tc">parody:</td><td></td></tr>' +
        '<tr><td class="tc">character:</td><td><a>nico yazawa</a></td></tr>' +
        '</table></div>';
      const groups = GalleryDetailParser.parseTagGroups(html);
      expect(groups.length).assertEqual(1);
      expect(groups[0].namespace).assertEqual('character');
    });

    it('tagQueryOf_composes_namespaced_tag', 0, () => {
      expect(tagQueryOf('female', 'lingerie')).assertEqual('female:lingerie');
      expect(tagQueryOf('other', 'ai generated')).assertEqual('other:ai generated');
    });

    it('parseTagGroups_row_without_namespace_goes_other', 0, () => {
      const html: string = '<div id="taglist"><table>' +
        '<tr><td><a>stray tag</a></td></tr>' +
        '</table></div>';
      const groups = GalleryDetailParser.parseTagGroups(html);
      expect(groups.length).assertEqual(1);
      expect(groups[0].namespace).assertEqual('other');
      expect(groups[0].tags.length).assertEqual(1);
      expect(groups[0].tags[0]).assertEqual('stray tag');
    });

    it('parseCover_extracts_fixture_cover', 0, () => {
      expect(GalleryDetailParser.parseCover(GALLERY_DETAIL_HTML))
        .assertEqual('https://ehgt.org/w/02/715/61558-qd609ha1.webp');
    });

    it('parseCover_missing_gd1_returns_empty', 0, () => {
      expect(GalleryDetailParser.parseCover('<div id="gd1"></div>')).assertEqual('');
      expect(GalleryDetailParser.parseCover('<html><body>no cover here</body></html>')).assertEqual('');
    });

    it('parseCover_style_without_url_returns_empty', 0, () => {
      expect(GalleryDetailParser.parseCover('<div id="gd1"><div style="width:10px"></div></div>'))
        .assertEqual('');
    });

    it('parseCover_skips_styleless_divs', 0, () => {
      expect(GalleryDetailParser.parseCover('<div id="gd1"><div><div style="width:250px; height:171px; background:transparent url(https://ehgt.org/x/y.webp) 0 0 no-repeat"></div></div></div>'))
        .assertEqual('https://ehgt.org/x/y.webp');
    });

    it('parsePreviews_fixture', 0, () => {
      const items: PreviewItem[] = GalleryDetailParser.parsePreviews(GALLERY_DETAIL_HTML, 4253086);
      expect(items.length).assertEqual(20);
      expect(items[0].page).assertEqual(0);
      expect(items[0].pToken).assertEqual('bb9f06e264');
      expect(items[0].imageUrl.includes('4253086-0.webp')).assertTrue();
      expect(items[19].page).assertEqual(19);
    });

    it('parsePreviews_cell_geometry', 0, () => {
      const items: PreviewItem[] = GalleryDetailParser.parsePreviews(GALLERY_DETAIL_HTML, 4253086);
      expect(items[0].x).assertEqual(0);
      expect(items[0].y).assertEqual(0);
      expect(items[0].w).assertEqual(200);
      expect(items[0].h).assertEqual(137);
      expect(items[1].x).assertEqual(200);
    });

    it('parsePreviews_missing_gdt_returns_empty', 0, () => {
      expect(GalleryDetailParser.parsePreviews('<html><body>no previews</body></html>', 1).length)
        .assertEqual(0);
    });

    it('parsePreviews_strips_quoted_url', 0, () => {
      const html: string = '<div id="gdt"><a href="https://e-hentai.org/s/bb9f06e264/9-1">' +
        '<div style=\'width:200px;height:100px;background:transparent url("https://ehgt.org/q/w.webp") -0px 0\'></div></a></div>';
      const items: PreviewItem[] = GalleryDetailParser.parsePreviews(html, 9);
      expect(items.length).assertEqual(1);
      expect(items[0].imageUrl).assertEqual('https://ehgt.org/q/w.webp');
    });

    it('parsePreviews_skips_cells_without_geometry', 0, () => {
      const html: string = '<div id="gdt">' +
        '<a href="https://e-hentai.org/s/bb9f06e264/9-1"><div style="background:transparent url(https://ehgt.org/q/w.webp)"></div></a>' +
        '<a href="https://e-hentai.org/s/a0113b5a19/9-2"><div style="width:200px; height:100px;background:transparent url(https://ehgt.org/q/v.webp) -0px 0 no-repeat"></div></a></div>';
      const items: PreviewItem[] = GalleryDetailParser.parsePreviews(html, 9);
      expect(items.length).assertEqual(1);
      expect(items[0].page).assertEqual(1);
      expect(items[0].w).assertEqual(200);
      expect(items[0].h).assertEqual(100);
    });

    it('missing_title_returns_null', 0, () => {
      expect(GalleryDetailParser.parse('<html><body>nope</body></html>', 1)).assertNull();
    });

    it('missing_api_keys_default_to_guest', 0, () => {
      const d: GalleryDetail | null =
        GalleryDetailParser.parse('<html><body><div id="gn">T</div></body></html>', 1, 'tok');
      expect(d !== null).assertTrue();
      expect(d?.apiUid).assertEqual(-1);
      expect(d?.apiKey).assertEqual('');
    });

    it('pages_from_length_row', 0, () => {
      const html: string = '<html><body><div id="gn">T</div><table><tr><td class="gdt1">Length:</td>' +
        '<td class="gdt2">1012 pages</td></tr></table></body></html>';
      expect(GalleryDetailParser.parse(html, 1)?.pages).assertEqual(1012);
    });

    it('pages_from_length_row_with_comma', 0, () => {
      const html: string = '<html><body><div id="gn">T</div><table><tr><td class="gdt1">Length:</td>' +
        '<td class="gdt2">1,012 pages</td></tr></table></body></html>';
      expect(GalleryDetailParser.parse(html, 1)?.pages).assertEqual(1012);
    });

    it('parseTagGroups_strips_english_suffix_after_pipe', 0, () => {
      const html: string = '<div id="taglist"><table>' +
        '<tr><td class="tc">character:</td><td>' +
        '<a>tsaritsa | anastasya feodorovna snezhnaya</a></td></tr>' +
        '</table></div>';
      const groups = GalleryDetailParser.parseTagGroups(html);
      expect(groups.length).assertEqual(1);
      expect(groups[0].namespace).assertEqual('character');
      expect(groups[0].tags.length).assertEqual(1);
      expect(groups[0].tags[0]).assertEqual('tsaritsa');
    });

    it('parseTagGroups_pipe_only_tag_skipped', 0, () => {
      const html: string = '<div id="taglist"><table>' +
        '<tr><td class="tc">other:</td><td><a>| alias only</a></td></tr>' +
        '</table></div>';
      expect(GalleryDetailParser.parseTagGroups(html).length).assertEqual(0);
    });

    it('favorite_state_from_gdf_not_favorited', 0, () => {
      const html: string = '<html><body><div id="gn">T</div>' +
        '<div id="gdf">Add to Favorites</div></body></html>';
      const d: GalleryDetail | null = GalleryDetailParser.parse(html, 1);
      expect(d?.isFavorited).assertFalse();
      expect(d?.favoriteName).assertEqual('');
    });

    it('favorite_state_from_gdf_favorited_with_name', 0, () => {
      const html: string = '<html><body><div id="gn">T</div>' +
        '<div id="gdf">Favorites 3</div></body></html>';
      const d: GalleryDetail | null = GalleryDetailParser.parse(html, 1);
      expect(d?.isFavorited).assertTrue();
      expect(d?.favoriteName).assertEqual('Favorites 3');
    });

    it('favorite_state_missing_gdf_defaults_false', 0, () => {
      const html: string = '<html><body><div id="gn">T</div></body></html>';
      const d: GalleryDetail | null = GalleryDetailParser.parse(html, 1);
      expect(d?.isFavorited).assertFalse();
      expect(d?.favoriteName).assertEqual('');
    });
  });
}
