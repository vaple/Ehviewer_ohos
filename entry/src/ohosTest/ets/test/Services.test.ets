import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { UIAbility, common } from '@kit.AbilityKit';
import { Logger } from '../../../main/ets/common/Logger';
import { CookieStore } from '../../../main/ets/network/CookieStore';

async function abilityContext(): Promise<common.Context> {
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  return ability.context;
}

export default function servicesTest() {
  describe('Services', () => {
    it('logger_does_not_throw', 0, () => {
      Logger.info('ServicesTest', 'hello');
      Logger.error('ServicesTest', 'hello');
      expect(true).assertTrue();
    });

    it('cookiestore_set_all_remove_roundtrip', 0, async () => {
      const store: CookieStore = new CookieStore();
      await store.init(await abilityContext());

      store.set('ipb_member_id', '42');
      expect(store.has('ipb_member_id')).assertTrue();
      expect(store.get('ipb_member_id')).assertEqual('42');
      expect(store.all()['ipb_member_id']).assertEqual('42');

      store.remove('ipb_member_id');
      await store.flush();
      expect(store.has('ipb_member_id')).assertFalse();
    });

    it('cookiestore_flush_is_readable_by_a_new_instance', 0, async () => {
      // 这一条替代了随 `Prefs` 一起删掉的 preferences 往返测试：证明 CookieStore 的**落盘**真的可读回。
      const store: CookieStore = new CookieStore();
      await store.init(await abilityContext());
      store.set('test_persist_key', 'v1');
      await store.flush();

      const reopened: CookieStore = new CookieStore();
      await reopened.init(await abilityContext());
      expect(reopened.get('test_persist_key')).assertEqual('v1');

      reopened.remove('test_persist_key');
      await reopened.flush();
      expect(reopened.has('test_persist_key')).assertFalse();
    });
  });
}
