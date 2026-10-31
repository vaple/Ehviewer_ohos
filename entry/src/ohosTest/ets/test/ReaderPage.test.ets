import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { UIAbility, common } from '@kit.AbilityKit';
import { RcpHttpClient } from '../../../main/ets/network/RcpHttpClient';
import { CookieStore } from '../../../main/ets/network/CookieStore';
import { EhClient } from '../../../main/ets/network/EhClient';
import { DetailCache } from '../../../main/ets/network/DetailCache';
import { EhSite, EhUrl } from '../../../main/ets/network/EhUrl';
import { GalleryInfo } from '../../../main/ets/model/GalleryInfo';
import { GalleryDetail } from '../../../main/ets/model/GalleryDetail';
import { HttpResponse } from '../../../main/ets/network/HttpClient';
import { GalleryPageResult } from '../../../main/ets/parser/GalleryPageParser';

async function ctx(): Promise<common.Context> {
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  return ability.context;
}

export default function readerPageTest() {
  describe('ReaderPage', () => {
    it('get_gallery_page_from_real_detail', 0, async () => {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(await ctx());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies, new DetailCache(25, 0));

      const list: GalleryInfo[] = await client.getGalleryList(EhSite.E, EhUrl.frontPage(EhSite.E));
      expect(list.length > 0).assertTrue();
      const first: GalleryInfo = list[0];

      // 从详情页 HTML 里取首图 pToken
      const raw: HttpResponse =
        await new RcpHttpClient().get(EhUrl.galleryDetail(EhSite.E, first.gid, first.token));
      const m: RegExpMatchArray | null =
        raw.body.match(new RegExp('/s/([0-9a-f]{10})/' + first.gid + '-1'));
      expect(m !== null).assertTrue();
      if (m !== null) {
        const pToken: string = m[1];
        const page: GalleryPageResult = await client.getGalleryPage(EhSite.E, first.gid, 1, pToken);
        expect(page.imageUrl.startsWith('https://')).assertTrue();
        // 顺序翻页依赖：首页应能解析出下一页 pToken，并用它取到第 2 页
        expect(page.nextPToken !== null).assertTrue();
        if (page.nextPToken !== null) {
          const page2: GalleryPageResult =
            await client.getGalleryPage(EhSite.E, first.gid, 2, page.nextPToken, page.skipHathKey ?? undefined);
          expect(page2.imageUrl.startsWith('https://')).assertTrue();
        }
      }
    });

    it('chunk_preview_tokens_beyond_20', 0, async () => {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(await ctx());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies, new DetailCache(25, 0));
      const list: GalleryInfo[] = await client.getGalleryList(EhSite.E, EhUrl.frontPage(EhSite.E));
      expect(list.length > 0).assertTrue();

      let target: GalleryInfo | null = null;
      let pages: number = 0;
      const probe: number = list.length < 8 ? list.length : 8;
      for (let i = 0; i < probe; i++) {
        const d: GalleryDetail | null = await client.getGalleryDetail(EhSite.E, list[i].gid, list[i].token);
        if (d !== null && d.pages > 20) {
          target = list[i];
          pages = d.pages;
          break;
        }
      }
      expect(target !== null).assertTrue();
      if (target !== null) {
        // 第 21 页落在第 2 个预览分块（chunk = 1）
        const tokens: string[] = await client.getPreviewTokens(EhSite.E, target.gid, target.token, 1);
        expect(tokens.length > 20).assertTrue();
        expect(tokens[20] !== undefined).assertTrue();
        const pToken: string = tokens[20];
        const page: GalleryPageResult = await client.getGalleryPage(EhSite.E, target.gid, 21, pToken);
        expect(page.imageUrl.startsWith('https://')).assertTrue();
        expect(pages > 20).assertTrue();
      }
    });

    it('detail_exposes_preview_tokens', 0, async () => {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(await ctx());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies, new DetailCache(25, 0));
      const list: GalleryInfo[] = await client.getGalleryList(EhSite.E, EhUrl.frontPage(EhSite.E));
      const first: GalleryInfo = list[0];
      const detail: GalleryDetail | null =
        await client.getGalleryDetail(EhSite.E, first.gid, first.token);
      expect(detail !== null).assertTrue();
      expect((detail?.previewTokens.length ?? 0) > 0).assertTrue();
      expect(detail?.previewTokens[0] !== undefined).assertTrue();
    });
  });
}
