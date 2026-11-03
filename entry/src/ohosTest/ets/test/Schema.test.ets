import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { UIAbility, common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { DbHelper } from '../../../main/ets/db/DbHelper';

const TABLES: string[] = ['QUICK_SEARCH', 'FILTER', 'HISTORY', 'DOWNLOAD', 'DOWNLOAD_PAGE'];

/**
 * 线上 v1.1.0（`DB_VERSION = 6`）的建表语句，逐字来自那个 tag。
 * 迁移用例必须以**当时真实的**结构为输入，不能按现在的 schema 倒推一份（那样测的是想象）。
 */
const V6_SCHEMA: string[] = [
  'CREATE TABLE IF NOT EXISTS QUICK_SEARCH (' +
    '_id INTEGER PRIMARY KEY AUTOINCREMENT, NAME TEXT, MODE INTEGER NOT NULL, CATEGORY INTEGER NOT NULL, ' +
    'KEYWORD TEXT, LANGUAGE TEXT, ADVANCE_SEARCH INTEGER NOT NULL, MIN_RATING INTEGER NOT NULL, ' +
    'PAGE_FROM INTEGER NOT NULL, PAGE_TO INTEGER NOT NULL, TIME INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS FILTER (' +
    '_id INTEGER PRIMARY KEY AUTOINCREMENT, MODE INTEGER NOT NULL, TEXT TEXT, ENABLE INTEGER)',
  'CREATE TABLE IF NOT EXISTS HISTORY (' +
    'GID INTEGER PRIMARY KEY NOT NULL, TOKEN TEXT, TITLE TEXT, TITLE_JPN TEXT, THUMB TEXT, CATEGORY INTEGER, ' +
    'POSTED TEXT, UPLOADER TEXT, RATING REAL, SIMPLE_LANGUAGE TEXT, MODE INTEGER, TIME INTEGER)',
  'CREATE TABLE IF NOT EXISTS DOWNLOAD (' +
    'GID INTEGER PRIMARY KEY NOT NULL, TOKEN TEXT, TITLE TEXT, CATEGORY INTEGER, PAGES INTEGER, ' +
    'QUALITY INTEGER, STATE INTEGER, DONE_PAGES INTEGER, FAILED_PAGES INTEGER, BYTES INTEGER, ' +
    'CREATED_AT INTEGER, UPDATED_AT INTEGER, DIR TEXT, THUMB TEXT, THUMB_URL TEXT)',
  'CREATE TABLE IF NOT EXISTS DOWNLOAD_PAGE (' +
    'GID INTEGER NOT NULL, PAGE INTEGER NOT NULL, FILE TEXT, BYTES INTEGER, STATE INTEGER, ' +
    'PRIMARY KEY (GID, PAGE))'
];

async function ctx(): Promise<common.Context> {
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  return ability.context;
}

/** 表的列名（`PRAGMA table_info`）。 */
async function columnsOf(store: relationalStore.RdbStore, table: string): Promise<string[]> {
  const rs: relationalStore.ResultSet = await store.querySql(`PRAGMA table_info(${table})`);
  const out: string[] = [];
  try {
    const nameIndex: number = rs.getColumnIndex('name');
    while (rs.goToNextRow()) {
      out.push(rs.getString(nameIndex));
    }
  } finally {
    rs.close();
  }
  return out;
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

    it('migrates_v6_to_v7_preserving_rows', 0, async () => {
      const store: relationalStore.RdbStore =
        await relationalStore.getRdbStore(await ctx(), { name: 'schema_probe.db', securityLevel: relationalStore.SecurityLevel.S1 });
      try {
        // 造一个"线上 v1.1.0 用户"的库：v6 结构 + 每张要改的表都塞一行。
        for (let i = 0; i < TABLES.length; i++) {
          await store.executeSql(`DROP TABLE IF EXISTS ${TABLES[i]}`);
        }
        for (let i = 0; i < V6_SCHEMA.length; i++) {
          await store.executeSql(V6_SCHEMA[i]);
        }
        await store.executeSql(
          'INSERT INTO QUICK_SEARCH (NAME, MODE, CATEGORY, KEYWORD, LANGUAGE, ADVANCE_SEARCH, MIN_RATING, ' +
          'PAGE_FROM, PAGE_TO, TIME) VALUES (?,?,?,?,?,?,?,?,?,?)',
          ['name1', 2, 0, 'kw1', 'chinese', 3, 4, -1, -1, 111]);
        await store.executeSql('INSERT INTO FILTER (MODE, TEXT, ENABLE) VALUES (?,?,?)', [0, 'loli', 1]);
        await store.executeSql(
          'INSERT INTO HISTORY (GID, TOKEN, TITLE, TITLE_JPN, THUMB, CATEGORY, POSTED, UPLOADER, RATING, ' +
          'SIMPLE_LANGUAGE, MODE, TIME) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
          [42, 'tok', 'T', '', 'th', 1, '2024', 'up', 4.5, 'EN', 0, 222]);
        store.version = 6;

        await DbHelper.ensureSchema(store);

        // 死列必须消失
        const qsCols: string[] = await columnsOf(store, 'QUICK_SEARCH');
        expect(qsCols.indexOf('MODE')).assertEqual(-1);
        expect(qsCols.indexOf('NAME')).assertEqual(-1);
        expect(qsCols.indexOf('PAGE_FROM')).assertEqual(-1);
        expect(qsCols.indexOf('PAGE_TO')).assertEqual(-1);
        expect((await columnsOf(store, 'FILTER')).indexOf('MODE')).assertEqual(-1);
        const hisCols: string[] = await columnsOf(store, 'HISTORY');
        expect(hisCols.indexOf('MODE')).assertEqual(-1);
        expect(hisCols.indexOf('TITLE_JPN')).assertEqual(-1);
        expect(hisCols.indexOf('PAGES') >= 0).assertTrue();

        // 原有行（含被保留的列值）必须还在
        const qs: relationalStore.ResultSet =
          await store.querySql('SELECT KEYWORD, LANGUAGE, ADVANCE_SEARCH, MIN_RATING FROM QUICK_SEARCH');
        try {
          expect(qs.goToFirstRow()).assertTrue();
          expect(qs.getString(qs.getColumnIndex('KEYWORD'))).assertEqual('kw1');
          expect(qs.getString(qs.getColumnIndex('LANGUAGE'))).assertEqual('chinese');
          expect(qs.getLong(qs.getColumnIndex('ADVANCE_SEARCH'))).assertEqual(3);
          expect(qs.getLong(qs.getColumnIndex('MIN_RATING'))).assertEqual(4);
        } finally {
          qs.close();
        }
        const flt: relationalStore.ResultSet = await store.querySql('SELECT TEXT, ENABLE FROM FILTER');
        try {
          expect(flt.goToFirstRow()).assertTrue();
          expect(flt.getString(flt.getColumnIndex('TEXT'))).assertEqual('loli');
          expect(flt.getLong(flt.getColumnIndex('ENABLE'))).assertEqual(1);
        } finally {
          flt.close();
        }
        const his: relationalStore.ResultSet =
          await store.querySql('SELECT TITLE, PAGES, TIME FROM HISTORY');
        try {
          expect(his.goToFirstRow()).assertTrue();
          expect(his.getString(his.getColumnIndex('TITLE'))).assertEqual('T');
          expect(his.getLong(his.getColumnIndex('PAGES'))).assertEqual(0);
          expect(his.getLong(his.getColumnIndex('TIME'))).assertEqual(222);
        } finally {
          his.close();
        }

        // 新结构能直接插入（老结构下这些列是 NOT NULL，漏填会撞约束）
        await store.executeSql(
          'INSERT INTO QUICK_SEARCH (CATEGORY, KEYWORD, LANGUAGE, ADVANCE_SEARCH, MIN_RATING, TIME) ' +
          'VALUES (?,?,?,?,?,?)', [0, 'kw2', '', 0, -1, 333]);
        await store.executeSql('INSERT INTO FILTER (TEXT, ENABLE) VALUES (?,?)', ['shota', 1]);
      } finally {
        store.close();
      }
    });
  });
}
