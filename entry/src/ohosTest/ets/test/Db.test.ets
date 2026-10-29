import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { UIAbility, common } from '@kit.AbilityKit';
import { DbHelper } from '../../../main/ets/db/DbHelper';
import { QuickSearchDao } from '../../../main/ets/db/dao/QuickSearchDao';
import { QuickSearch } from '../../../main/ets/model/QuickSearch';

async function abilityContext(): Promise<common.Context> {
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  return ability.context;
}

export default function dbTest() {
  describe('Db', () => {
    it('insert_then_queryAll_returns_exact_row', 0, async () => {
      await DbHelper.init(await abilityContext());
      await QuickSearchDao.deleteAll();

      const qs: QuickSearch = {
        id: 0, name: 'name1', mode: 0, category: 0, keyword: 'kw1', language: '',
        advanceSearch: 0, minRating: 0, pageFrom: -1, pageTo: -1, time: 123
      };
      const rowId: number = await QuickSearchDao.insert(qs);
      expect(rowId > 0).assertTrue();

      const all: QuickSearch[] = await QuickSearchDao.queryAll();
      expect(all.length).assertEqual(1);
      expect(all[0].name).assertEqual('name1');
      expect(all[0].keyword).assertEqual('kw1');
      expect(all[0].time).assertEqual(123);
    });
  });
}
