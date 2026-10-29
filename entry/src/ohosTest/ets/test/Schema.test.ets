import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { UIAbility, common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { DbHelper } from '../../../main/ets/db/DbHelper';

const TABLES: string[] = ['QUICK_SEARCH', 'FILTER', 'HISTORY', 'DOWNLOAD', 'DOWNLOAD_PAGE'];

async function ctx(): Promise<common.Context> {
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  return ability.context;
}

export default function schemaTest() {
  describe('Schema', () => {
    it('all_mvp_tables_exist', 0, async () => {
      await DbHelper.init(await ctx());
      const store: relationalStore.RdbStore = DbHelper.getStore();

      for (let i = 0; i < TABLES.length; i++) {
        const rs: relationalStore.ResultSet = await store.querySql(`SELECT count(*) AS c FROM ${TABLES[i]}`);
        try {
          expect(rs.goToFirstRow()).assertTrue();
        } finally {
          rs.close();
        }
      }
    });

    it('heals_legacy_p0_quick_search_schema', 0, async () => {
      const store: relationalStore.RdbStore =
        await relationalStore.getRdbStore(await ctx(), { name: 'legacy_probe.db', securityLevel: relationalStore.SecurityLevel.S1 });
      try {
        await store.executeSql('DROP TABLE IF EXISTS QUICK_SEARCH');
        await store.executeSql(
          'CREATE TABLE QUICK_SEARCH (ID INTEGER PRIMARY KEY AUTOINCREMENT, NAME TEXT, KEYWORD TEXT, TIME INTEGER)');

        await DbHelper.ensureSchema(store);

        await store.executeSql(
          "INSERT INTO QUICK_SEARCH (NAME, MODE, CATEGORY, KEYWORD, ADVANCE_SEARCH, MIN_RATING, PAGE_FROM, PAGE_TO, TIME) " +
          "VALUES ('n', 1, 0, 'k', 0, 0, -1, -1, 0)");
        const rs: relationalStore.ResultSet = await store.querySql('SELECT MODE FROM QUICK_SEARCH');
        try {
          expect(rs.goToFirstRow()).assertTrue();
          expect(rs.getLong(rs.getColumnIndex('MODE'))).assertEqual(1);
        } finally {
          rs.close();
        }
      } finally {
        store.close();
      }
    });
  });
}
