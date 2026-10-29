import { relationalStore } from '@kit.ArkData';
import { QuickSearch } from '../../model/QuickSearch';
import { DbHelper } from '../DbHelper';

const TABLE: string = 'QUICK_SEARCH';

/** `QUICK_SEARCH` 表的 DAO（真实列）。 */
export class QuickSearchDao {
  static async insert(qs: QuickSearch): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const values: relationalStore.ValuesBucket = {
      'NAME': qs.name,
      'MODE': qs.mode,
      'CATEGORY': qs.category,
      'KEYWORD': qs.keyword,
      'LANGUAGE': qs.language,
      'ADVANCE_SEARCH': qs.advanceSearch,
      'MIN_RATING': qs.minRating,
      'PAGE_FROM': qs.pageFrom,
      'PAGE_TO': qs.pageTo,
      'TIME': qs.time
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

  static async queryAll(): Promise<QuickSearch[]> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    const rows: QuickSearch[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const langIndex: number = resultSet.getColumnIndex('LANGUAGE');
        const row: QuickSearch = {
          id: resultSet.getLong(resultSet.getColumnIndex('_id')),
          name: resultSet.getString(resultSet.getColumnIndex('NAME')),
          mode: resultSet.getLong(resultSet.getColumnIndex('MODE')),
          category: resultSet.getLong(resultSet.getColumnIndex('CATEGORY')),
          keyword: resultSet.getString(resultSet.getColumnIndex('KEYWORD')),
          // v1 老行的 LANGUAGE 为 NULL（迁移新增列）→ 按空串处理。
          language: resultSet.isColumnNull(langIndex) ? '' : resultSet.getString(langIndex),
          advanceSearch: resultSet.getLong(resultSet.getColumnIndex('ADVANCE_SEARCH')),
          minRating: resultSet.getLong(resultSet.getColumnIndex('MIN_RATING')),
          pageFrom: resultSet.getLong(resultSet.getColumnIndex('PAGE_FROM')),
          pageTo: resultSet.getLong(resultSet.getColumnIndex('PAGE_TO')),
          time: resultSet.getLong(resultSet.getColumnIndex('TIME'))
        };
        rows.push(row);
      }
    } finally {
      resultSet.close();
    }
    return rows;
  }
}
