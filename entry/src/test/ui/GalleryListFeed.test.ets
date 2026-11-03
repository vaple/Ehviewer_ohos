import { describe, it, expect } from '@ohos/hypium';
import { GalleryListFeed } from '../../main/ets/ui/GalleryListFeed';
import { GalleryListPage } from '../../main/ets/parser/GalleryListParser';
import { GalleryInfo } from '../../main/ets/model/GalleryInfo';

/** 造一条最小可用的画廊条目（只关心 gid，其余字段留空）。 */
function info(gid: number): GalleryInfo {
  return {
    gid: gid,
    token: 'tok',
    title: `t${gid}`,
    thumb: '',
    category: 0,
    posted: '',
    uploader: '',
    rating: 0,
    simpleLanguage: '',
    pages: 0
  };
}

function page(gids: number[], next: string | null): GalleryListPage {
  const items: GalleryInfo[] = [];
  for (let i = 0; i < gids.length; i++) {
    items.push(info(gids[i]));
  }
  return { items: items, next: next };
}

export default function galleryListFeedTest() {
  describe('GalleryListFeed', () => {
    it('follows_next_until_null', 0, async () => {
      const calls: string[] = [];
      const feed = new GalleryListFeed(async (url: string): Promise<GalleryListPage> => {
        calls.push(url);
        if (url === 'p0') {
          return page([1, 2], 'p1');
        }
        if (url === 'p1') {
          return page([2, 3], 'p2');
        }
        return page([4], null);
      });

      await feed.load('p0', true);
      expect(calls.length).assertEqual(1);
      expect(feed.items.length).assertEqual(2);
      expect(feed.hasMore).assertTrue();

      await feed.load('p0', false);
      // 跨页重复的 gid 2 不能重复进列表。
      expect(feed.items.length).assertEqual(3);
      expect(feed.hasMore).assertTrue();

      await feed.load('p0', false);
      expect(feed.items.length).assertEqual(4);
      expect(feed.hasMore).assertFalse();

      // 到底之后再 load 不发请求。
      await feed.load('p0', false);
      expect(calls.length).assertEqual(3);
    });

    it('stops_when_next_points_back', 0, async () => {
      // 站点把越界页重定向回第 1 页时，next 会指回已访问 URL —— 这就算到底。
      const calls: string[] = [];
      const feed = new GalleryListFeed(async (url: string): Promise<GalleryListPage> => {
        calls.push(url);
        return url === 'a' ? page([1], 'b') : page([2], 'a');
      });

      await feed.load('a', true);
      await feed.load('a', false);
      expect(calls.length).assertEqual(2);
      expect(feed.hasMore).assertFalse();
      expect(feed.items.length).assertEqual(2);
    });

    it('refresh_restarts_from_first_url', 0, async () => {
      const calls: string[] = [];
      const feed = new GalleryListFeed(async (url: string): Promise<GalleryListPage> => {
        calls.push(url);
        return page([1], null);
      });
      await feed.load('first', true);
      await feed.load('first', true);
      expect(calls.length).assertEqual(2);
      expect(calls[1]).assertEqual('first');
      expect(feed.items.length).assertEqual(1);
    });
  });
}
