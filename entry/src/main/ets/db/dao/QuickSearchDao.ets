import { relationalStore } from '@kit.ArkData';
import { QuickSearch, SEARCH_HISTORY, SEARCH_SAVED } from '../../model/QuickSearch';
import { DbHelper } from '../DbHelper';

const TABLE: string = 'QUICK_SEARCH';

/**
 * `QUICK_SEARCH` 表的 DAO（真实列）。
 *
 * 快搜与搜索历史共用这张表（`SAVED` 区分）。**`SAVED` 条件只允许出现在这里**：
 * 页面拿到的永远是已经按用途过滤好的列表，没机会漏条件——漏一次的后果是
 * 历史混进快搜列表，或者快搜被历史的裁剪删掉。
 */
export class QuickSearchDao {
  static async insert(qs: QuickSearch): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const values: relationalStore.ValuesBucket = {
      'CATEGORY': qs.category,
      'KEYWORD': qs.keyword,
      'LANGUAGE': qs.language,
      'ADVANCE_SEARCH': qs.advanceSearch,
      'MIN_RATING': qs.minRating,
      'TIME': qs.time,
      'SAVED': qs.saved
    };
    return await store.insert(TABLE, values);
  }

  /** 删除全部行（保持测试自净 / 清空数据）。返回删除行数。 */
  static async deleteAll(): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    return await store.delete(predicates);
  }

  /** 按 id 删除单条（照 `FilterDao.delete` 现例）。 */
  static async delete(id: number): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('_id', id);
    return await store.delete(predicates);
  }

  /** 全部行（含历史；仅测试 / 排障用，页面走 `querySaved` / `queryHistory`）。 */
  static async queryAll(): Promise<QuickSearch[]> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    return await QuickSearchDao.rowsOf(new relationalStore.RdbPredicates(TABLE));
  }

  /** 手动保存的快搜（新的在前）。 */
  static async querySaved(): Promise<QuickSearch[]> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('SAVED', SEARCH_SAVED);
    predicates.orderByDesc('TIME');
    return await QuickSearchDao.rowsOf(predicates);
  }

  /** 搜索历史（新的在前，最多 `limit` 条）。 */
  static async queryHistory(limit: number): Promise<QuickSearch[]> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('SAVED', SEARCH_HISTORY);
    predicates.orderByDesc('TIME');
    predicates.limitAs(limit);
    return await QuickSearchDao.rowsOf(predicates);
  }

  /** 同一条搜索再搜一次：只更新时间（提到最前），不新增行。 */
  static async touch(id: number, time: number): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const values: relationalStore.ValuesBucket = { 'TIME': time };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('_id', id);
    return await store.update(values, predicates);
  }

  /** 删除超出上限的历史（只动 `SAVED=0`；快搜不受影响）。 */
  static async pruneHistory(ids: number[]): Promise<number> {
    if (ids.length === 0) {
      return 0;
    }
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('SAVED', SEARCH_HISTORY);
    predicates.in('_id', ids);
    return await store.delete(predicates);
  }

  /** 清空搜索历史（快搜保留）。 */
  static async clearHistory(): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('SAVED', SEARCH_HISTORY);
    return await store.delete(predicates);
  }

  private static async rowsOf(predicates: relationalStore.RdbPredicates): Promise<QuickSearch[]> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    const rows: QuickSearch[] = [];
    try {
      const langIndex: number = resultSet.getColumnIndex('LANGUAGE');
      const savedIndex: number = resultSet.getColumnIndex('SAVED');
      while (resultSet.goToNextRow()) {
        const row: QuickSearch = {
          id: resultSet.getLong(resultSet.getColumnIndex('_id')),
          category: resultSet.getLong(resultSet.getColumnIndex('CATEGORY')),
          keyword: resultSet.getString(resultSet.getColumnIndex('KEYWORD')),
          // v1 老行的 LANGUAGE 为 NULL（迁移新增列）→ 按空串处理。
          language: resultSet.isColumnNull(langIndex) ? '' : resultSet.getString(langIndex),
          advanceSearch: resultSet.getLong(resultSet.getColumnIndex('ADVANCE_SEARCH')),
          minRating: resultSet.getLong(resultSet.getColumnIndex('MIN_RATING')),
          time: resultSet.getLong(resultSet.getColumnIndex('TIME')),
          saved: resultSet.isColumnNull(savedIndex) ? SEARCH_SAVED : resultSet.getLong(savedIndex)
        };
        rows.push(row);
      }
    } finally {
      resultSet.close();
    }
    return rows;
  }
}
