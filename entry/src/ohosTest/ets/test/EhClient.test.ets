import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { UIAbility, common } from '@kit.AbilityKit';
import { RcpHttpClient } from '../../../main/ets/network/RcpHttpClient';
import { CookieStore } from '../../../main/ets/network/CookieStore';
import { EhClient } from '../../../main/ets/network/EhClient';
import { EhSite, EhUrl } from '../../../main/ets/network/EhUrl';
import { GalleryInfo } from '../../../main/ets/model/GalleryInfo';

async function ctx(): Promise<common.Context> {
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  return ability.context;
}

export default function ehClientTest() {
  describe('EhClient', () => {
    it('get_gallery_list_from_real_front_page', 0, async () => {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(await ctx());

      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      const list: GalleryInfo[] = await client.getGalleryList(EhSite.E, EhUrl.frontPage(EhSite.E));

      expect(list.length > 0).assertTrue();
      expect(list[0].gid > 0).assertTrue();
      expect(list[0].token.length).assertEqual(10);
    });

    it('gallery_detail_url', 0, () => {
      const client: EhClient = new EhClient(new RcpHttpClient(), new CookieStore());
      expect(client.getGalleryDetailUrl(EhSite.E, 123456, 'abcdef0123'))
        .assertEqual('https://e-hentai.org/g/123456/abcdef0123/');
    });
  });
}
