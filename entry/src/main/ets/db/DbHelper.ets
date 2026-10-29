import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppError } from '../common/AppError';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'ehviewer.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

const CREATE_STATEMENTS: string[] = [
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

/** RDB（`@ohos.data.relationalStore`）初始化、建表与版本骨架。 */
export class DbHelper {
  static readonly DB_VERSION: number = 6;

  private static store: relationalStore.RdbStore | undefined = undefined;

  /** 打开数据库并确保 schema 为当前版本；重复调用幂等。 */
  static async init(context: common.Context): Promise<void> {
    if (DbHelper.store !== undefined) {
      return;
    }
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
    await DbHelper.ensureSchema(store);
    DbHelper.store = store;
  }

  /**
   * 确保 schema 为当前版本：按已存版本走迁移分支，并对早期版本遗留的不兼容
   * `QUICK_SEARCH`（存在但缺 MODE 列）做自愈重建。供 `init` 使用，亦可单测。
   */
  static async ensureSchema(store: relationalStore.RdbStore): Promise<void> {
    const oldVersion: number = store.version;

    if (await DbHelper.isLegacyQuickSearch(store)) {
      // 检测到与当前 schema 不兼容的 QUICK_SEARCH（早期版本遗留）→ 自愈重建
      await store.executeSql('DROP TABLE IF EXISTS QUICK_SEARCH');
    } else if (oldVersion > 0 && oldVersion < DbHelper.DB_VERSION) {
      await DbHelper.migrate(store, oldVersion);
    }

    for (let i = 0; i < CREATE_STATEMENTS.length; i++) {
      await store.executeSql(CREATE_STATEMENTS[i]);
    }
    if (store.version < DbHelper.DB_VERSION) {
      store.version = DbHelper.DB_VERSION;
    }
  }

  /** 版本升级钩子：`fromVersion < DB_VERSION` 时的增量迁移入口。 */
  private static async migrate(store: relationalStore.RdbStore, fromVersion: number): Promise<void> {
    if (fromVersion < 2) {
      // 快搜增加语言 chip 条件（老记录 NULL → 读取时按空串处理）。
      await store.executeSql('ALTER TABLE QUICK_SEARCH ADD COLUMN LANGUAGE TEXT');
    }
    if (fromVersion < 3) {
      // 「搜索排除」取代本地屏蔽：命名空间模式无法用查询语法表达，清掉旧规则。
      await store.executeSql('DELETE FROM FILTER WHERE MODE = 3');
    }
    if (fromVersion < 4) {
      // 规则 text 统一成完整查询词（带 qualifier），UI 不再分「标题/上传者/标签」。
      await store.executeSql("UPDATE FILTER SET TEXT = 'uploader:' || TEXT WHERE MODE = 1");
      await store.executeSql("UPDATE FILTER SET TEXT = 'title:' || TEXT WHERE MODE = 0");
      await store.executeSql('UPDATE FILTER SET MODE = 0 WHERE MODE <> 0');
    }
    if (fromVersion === 5) {
      // 下载列表封面：只在 v5 的 DOWNLOAD 上补列（更老的库会按新 CREATE 语句直接建全）。
      await store.executeSql('ALTER TABLE DOWNLOAD ADD COLUMN THUMB TEXT');
      await store.executeSql('ALTER TABLE DOWNLOAD ADD COLUMN THUMB_URL TEXT');
    }
  }

  /** `QUICK_SEARCH` 存在且缺少 MODE 列 ⇒ 视为早期版本遗留结构。 */
  private static async isLegacyQuickSearch(store: relationalStore.RdbStore): Promise<boolean> {
    const resultSet: relationalStore.ResultSet = await store.querySql('PRAGMA table_info(QUICK_SEARCH)');
    let hasAnyColumn: boolean = false;
    let hasMode: boolean = false;
    try {
      const nameIndex: number = resultSet.getColumnIndex('name');
      while (resultSet.goToNextRow()) {
        hasAnyColumn = true;
        if (resultSet.getString(nameIndex) === 'MODE') {
          hasMode = true;
        }
      }
    } finally {
      resultSet.close();
    }
    return hasAnyColumn && !hasMode;
  }

  static getStore(): relationalStore.RdbStore {
    if (DbHelper.store === undefined) {
      throw new AppError(-1, 'DbHelper.init() must be called before getStore()');
    }
    return DbHelper.store;
  }
}
