import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppError } from '../common/AppError';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'ehviewer.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

/** 库里的全部表（超出保留窗口时整库重建用）。 */
const TABLES: string[] = ['QUICK_SEARCH', 'FILTER', 'HISTORY', 'DOWNLOAD', 'DOWNLOAD_PAGE'];

/**
 * 建表语句必须是**当前**结构。
 * 迁移走 `ALTER TABLE ... DROP COLUMN`（SQLite 3.35+），它改不了约束，所以这里的列约束必须和
 * "老表 + 迁移语句"跑完后的结果一致，否则全新安装与升级安装会得到两套不同约束的库。
 */
const CREATE_STATEMENTS: string[] = [
  'CREATE TABLE IF NOT EXISTS QUICK_SEARCH (' +
    '_id INTEGER PRIMARY KEY AUTOINCREMENT, CATEGORY INTEGER NOT NULL, ' +
    'KEYWORD TEXT, LANGUAGE TEXT, ADVANCE_SEARCH INTEGER NOT NULL, MIN_RATING INTEGER NOT NULL, ' +
    'TIME INTEGER NOT NULL)',

  'CREATE TABLE IF NOT EXISTS FILTER (' +
    '_id INTEGER PRIMARY KEY AUTOINCREMENT, TEXT TEXT, ENABLE INTEGER)',

  'CREATE TABLE IF NOT EXISTS HISTORY (' +
    'GID INTEGER PRIMARY KEY NOT NULL, TOKEN TEXT, TITLE TEXT, THUMB TEXT, CATEGORY INTEGER, ' +
    'POSTED TEXT, UPLOADER TEXT, RATING REAL, SIMPLE_LANGUAGE TEXT, TIME INTEGER, ' +
    'PAGES INTEGER NOT NULL DEFAULT 0)',

  'CREATE TABLE IF NOT EXISTS DOWNLOAD (' +
    'GID INTEGER PRIMARY KEY NOT NULL, TOKEN TEXT, TITLE TEXT, CATEGORY INTEGER, PAGES INTEGER, ' +
    'QUALITY INTEGER, STATE INTEGER, DONE_PAGES INTEGER, FAILED_PAGES INTEGER, BYTES INTEGER, ' +
    'CREATED_AT INTEGER, UPDATED_AT INTEGER, DIR TEXT, THUMB TEXT, THUMB_URL TEXT)',

  'CREATE TABLE IF NOT EXISTS DOWNLOAD_PAGE (' +
    'GID INTEGER NOT NULL, PAGE INTEGER NOT NULL, FILE TEXT, BYTES INTEGER, STATE INTEGER, ' +
    'PRIMARY KEY (GID, PAGE))'
];

/**
 * 一条迁移：把 `from` 版升到 `from + 1`。
 *
 * **数组长度就是保留窗口**：`store.version < STEPS[0].from` 的库不再逐版本升级，直接整库重建
 * ——宁可清空，也不能留下半新半旧的结构（那会在运行期以"列不存在"炸掉）。
 *
 * 纪律：本项目已发版（v1.0.0 / v1.1.0 的线上库都是 v6），因此**只允许在末尾追加，不允许删除**。
 * 删掉一条 = 停留在那个版本的设备被整库重建，那是真实的用户数据。
 */
interface MigrationStep {
  from: number;
  sql: string[];
}

const STEPS: MigrationStep[] = [
  {
    // v6 → v7：清掉 Android 时代遗留、移植后只写不读的列，并补上历史页缺的 PAGES。
    from: 6,
    sql: [
      // 快搜：MODE（入口模式）与 NAME（恒等于 KEYWORD）都已是死字段；页数区间从未落库也从未恢复。
      'ALTER TABLE QUICK_SEARCH DROP COLUMN MODE',
      'ALTER TABLE QUICK_SEARCH DROP COLUMN NAME',
      'ALTER TABLE QUICK_SEARCH DROP COLUMN PAGE_FROM',
      'ALTER TABLE QUICK_SEARCH DROP COLUMN PAGE_TO',
      // 屏蔽规则：规则文本已是完整查询词，MODE（0 标题/1 上传者/2 标签）不再参与任何拼接。
      'ALTER TABLE FILTER DROP COLUMN MODE',
      // 历史：MODE 从未被读；TITLE_JPN 解析并落库但全项目没有任何一处显示。
      'ALTER TABLE HISTORY DROP COLUMN MODE',
      'ALTER TABLE HISTORY DROP COLUMN TITLE_JPN',
      // 历史页一直写死 `pages: 0`（列都不存在），补上后列表才会显示页数。
      'ALTER TABLE HISTORY ADD COLUMN PAGES INTEGER NOT NULL DEFAULT 0'
    ]
  }
];

/** RDB（`@ohos.data.relationalStore`）初始化、建表与版本骨架。 */
export class DbHelper {
  static readonly DB_VERSION: number = 7;

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
   * 确保 schema 为当前版本。供 `init` 使用，亦可单测。
   *
   * 官方要求：`version` 的读写各占一次数据库连接，所以只在开头读一次、结尾写一次，
   * 中间全部用临时变量。
   */
  static async ensureSchema(store: relationalStore.RdbStore): Promise<void> {
    const oldVersion: number = store.version;

    if (oldVersion > 0 && oldVersion < DbHelper.DB_VERSION) {
      if (oldVersion < DbHelper.oldestSupported()) {
        // 超出保留窗口：整库重建（不猜中间态）
        for (let i = 0; i < TABLES.length; i++) {
          await store.executeSql(`DROP TABLE IF EXISTS ${TABLES[i]}`);
        }
      } else {
        await DbHelper.applySteps(store, oldVersion);
      }
    }

    for (let i = 0; i < CREATE_STATEMENTS.length; i++) {
      await store.executeSql(CREATE_STATEMENTS[i]);
    }
    if (oldVersion < DbHelper.DB_VERSION) {
      store.version = DbHelper.DB_VERSION;
    }
  }

  /** 保留窗口的下界：最早的被支持版本（= 第一条 step 的起点）。 */
  private static oldestSupported(): number {
    return STEPS.length > 0 ? STEPS[0].from : DbHelper.DB_VERSION;
  }

  /**
   * 依次执行 `from` 起的全部 step。
   * 必须包在事务里：中途失败又不写 version，下次启动会从第一条重跑，
   * 而 `DROP COLUMN` 重跑会报 `no such column` → 启动永久失败。
   */
  private static async applySteps(store: relationalStore.RdbStore, fromVersion: number): Promise<void> {
    store.beginTransaction();
    try {
      for (let i = 0; i < STEPS.length; i++) {
        const step: MigrationStep = STEPS[i];
        if (step.from < fromVersion) {
          continue;
        }
        for (let j = 0; j < step.sql.length; j++) {
          await store.executeSql(step.sql[j]);
        }
      }
      store.commit();
    } catch (e) {
      store.rollBack();
      throw e as Error;
    }
  }

  static getStore(): relationalStore.RdbStore {
    if (DbHelper.store === undefined) {
      throw new AppError(-1, 'DbHelper.init() must be called before getStore()');
    }
    return DbHelper.store;
  }
}
