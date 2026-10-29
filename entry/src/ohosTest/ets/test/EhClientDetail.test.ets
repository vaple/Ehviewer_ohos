import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { UIAbility, common } from '@kit.AbilityKit';
import { RcpHttpClient } from '../../../main/ets/network/RcpHttpClient';
import { CookieStore } from '../../../main/ets/network/CookieStore';
import { EhClient } from '../../../main/ets/network/EhClient';
import { EhSite, EhUrl } from '../../../main/ets/network/EhUrl';
import { GalleryInfo } from '../../../main/ets/model/GalleryInfo';
import { GalleryDetail } from '../../../main/ets/model/GalleryDetail';

async function ctx(): Promise<common.Context> {
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  return ability.context;
}

export default function ehClientDetailTest() {
  describe('EhClientDetail', () => {
    it('fetch_list_then_detail', 0, async () => {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(await ctx());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);

      const list: GalleryInfo[] = await client.getGalleryList(EhSite.E, EhUrl.frontPage(EhSite.E));
      expect(list.length > 0).assertTrue();

      const first: GalleryInfo = list[0];
      const detail: GalleryDetail | null = await client.getGalleryDetail(EhSite.E, first.gid, first.token);
      expect(detail !== null).assertTrue();
      if (detail !== null) {
        expect(detail.gid).assertEqual(first.gid);
        expect(detail.title.length > 0).assertTrue();
        expect(detail.pages > 0).assertTrue();
      }
    });
  });
}
