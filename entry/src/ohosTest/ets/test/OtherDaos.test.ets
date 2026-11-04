import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { UIAbility, common } from '@kit.AbilityKit';
import { DbHelper } from '../../../main/ets/db/DbHelper';
import { QuickSearchDao } from '../../../main/ets/db/dao/QuickSearchDao';
import { FilterDao } from '../../../main/ets/db/dao/FilterDao';
import { QuickSearch } from '../../../main/ets/model/QuickSearch';
import { Filter } from '../../../main/ets/model/Filter';

async function ctx(): Promise<common.Context> {
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  return ability.context;
}

export default function otherDaosTest() {
  describe('OtherDaos', () => {
    it('quick_search_real_columns_roundtrip', 0, async () => {
      await DbHelper.init(await ctx());
      await QuickSearchDao.deleteAll();
      const qs: QuickSearch = {
        id: 0, category: 2, keyword: 'kw', language: 'chinese',
        advanceSearch: 1, minRating: 4, time: 999, saved: 1
      };
      await QuickSearchDao.insert(qs);
      const all: QuickSearch[] = await QuickSearchDao.queryAll();
      expect(all.length).assertEqual(1);
      expect(all[0].category).assertEqual(2);
      expect(all[0].language).assertEqual('chinese');
      expect(all[0].advanceSearch).assertEqual(1);
      expect(all[0].minRating).assertEqual(4);
    });

    it('search_history_and_saved_do_not_cross', 0, async () => {
      await DbHelper.init(await ctx());
      await QuickSearchDao.deleteAll();
      const saved: QuickSearch = {
        id: 0, category: 0, keyword: 'keep', language: '',
        advanceSearch: 0, minRating: -1, time: 1, saved: 1
      };
      const history: QuickSearch = {
        id: 0, category: 0, keyword: 'gone', language: '',
        advanceSearch: 0, minRating: -1, time: 2, saved: 0
      };
      await QuickSearchDao.insert(saved);
      await QuickSearchDao.insert(history);

      const savedRows: QuickSearch[] = await QuickSearchDao.querySaved();
      expect(savedRows.length).assertEqual(1);
      expect(savedRows[0].keyword).assertEqual('keep');
      const historyRows: QuickSearch[] = await QuickSearchDao.queryHistory(50);
      expect(historyRows.length).assertEqual(1);
      expect(historyRows[0].keyword).assertEqual('gone');

      // 清空历史不能动快搜。
      await QuickSearchDao.clearHistory();
      expect((await QuickSearchDao.queryHistory(50)).length).assertEqual(0);
      expect((await QuickSearchDao.querySaved()).length).assertEqual(1);
      await QuickSearchDao.deleteAll();
    });

    it('filter_add_query_toggle_delete', 0, async () => {
      await DbHelper.init(await ctx());
      await FilterDao.clear();
      const f: Filter = { id: 0, text: 'lolicon', enable: true };
      const id: number = await FilterDao.add(f);
      expect(id > 0).assertTrue();
      const all: Filter[] = await FilterDao.queryAll();
      expect(all.length).assertEqual(1);
      expect(all[0].text).assertEqual('lolicon');
      expect(all[0].enable).assertTrue();
      await FilterDao.setEnabled(id, false);
      expect((await FilterDao.queryAll())[0].enable).assertFalse();
      await FilterDao.delete(id);
      expect((await FilterDao.queryAll()).length).assertEqual(0);
    });
  });
}
