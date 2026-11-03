import { describe, it, expect } from '@ohos/hypium';
import { GalleryListParser, GalleryListPage } from '../../main/ets/parser/GalleryListParser';
import { SEARCH_FIRST } from '../fixtures/list/search-first';
import { SEARCH_NOHITS } from '../fixtures/list/search-nohits';
import { TOPLIST_FIRST } from '../fixtures/list/toplist-first';
import { TOPLIST_LAST } from '../fixtures/list/toplist-last';
import { WATCHED_SINGLE } from '../fixtures/list/watched-single';

/**
 * 分页判据：**跟着页面给的 next 走**，`next === null` 就是到底。
 *
 * 五个 fixture 都是真机（登录态）抓的原始响应，不脱敏、不裁剪：
 * - `toplist-*` 用 `table.ptt`（最后一格是 `>` 箭头）；
 * - `search-*` / `watched-*` 用 `div.searchnav` 的 `a#dnext`（单页时它是 `<span>`）。
 */
export default function galleryListPageTest() {
  describe('GalleryListPage', () => {
    it('toplist_first_page_has_next_from_ptt', 0, () => {
      const page: GalleryListPage = GalleryListParser.parsePage(TOPLIST_FIRST, 0);
      expect(page.items.length).assertEqual(50);
      expect(page.next !== null).assertTrue();
      if (page.next !== null) {
        expect(page.next.indexOf('toplist.php') >= 0).assertTrue();
        expect(page.next.indexOf('p=1') >= 0).assertTrue();
      }
    });

    it('toplist_last_page_has_no_next', 0, () => {
      // 末页的 `>` 退化成纯文本，没有 `<a>` → next 必须是 null（不能靠"本页没新增"猜）。
      const page: GalleryListPage = GalleryListParser.parsePage(TOPLIST_LAST, 0);
      expect(page.items.length).assertEqual(50);
      expect(page.next === null).assertTrue();
    });

    it('search_first_page_has_next_from_dnext', 0, () => {
      const page: GalleryListPage = GalleryListParser.parsePage(SEARCH_FIRST, 0);
      expect(page.items.length > 0).assertTrue();
      expect(page.next !== null).assertTrue();
      if (page.next !== null) {
        // 搜索分页是游标：`?f_search=…&next=<gid>`，不是页码。
        expect(page.next.indexOf('next=') >= 0).assertTrue();
      }
    });

    it('watched_single_page_has_no_next', 0, () => {
      // 订阅是单页：`<span id="dnext">` 没有 href → null。旧实现按 `page++` 硬翻，
      // 每页都返回同一份 10 条（真机日志曾翻到 page=8592）。
      const page: GalleryListPage = GalleryListParser.parsePage(WATCHED_SINGLE, 0);
      expect(page.items.length).assertEqual(10);
      expect(page.next === null).assertTrue();
    });

    it('no_hits_gives_empty_page', 0, () => {
      const page: GalleryListPage = GalleryListParser.parsePage(SEARCH_NOHITS, 0);
      expect(page.items.length).assertEqual(0);
      expect(page.next === null).assertTrue();
    });

    it('parse_keeps_items_only_api', 0, () => {
      // 旧的 `parse()` 保留为薄封装，别让既有调用点改签名。
      expect(GalleryListParser.parse(WATCHED_SINGLE, 0).length).assertEqual(10);
    });
  });
}
