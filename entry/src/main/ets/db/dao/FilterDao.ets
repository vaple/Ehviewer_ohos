import { relationalStore } from '@kit.ArkData';
import { Filter } from '../../model/Filter';
import { DbHelper } from '../DbHelper';

const TABLE: string = 'FILTER';

/** `FILTER` 表的 DAO。 */
export class FilterDao {
  static async add(filter: Filter): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const values: relationalStore.ValuesBucket = {
      'MODE': filter.mode,
      'TEXT': filter.text,
      'ENABLE': filter.enable ? 1 : 0
    };
    return await store.insert(TABLE, values);
  }

  static async queryAll(): Promise<Filter[]> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const resultSet: relationalStore.ResultSet =
      await store.querySql(`SELECT _id, MODE, TEXT, ENABLE FROM ${TABLE}`);
    const rows: Filter[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const row: Filter = {
          id: resultSet.getLong(resultSet.getColumnIndex('_id')),
          mode: resultSet.getLong(resultSet.getColumnIndex('MODE')),
          text: resultSet.getString(resultSet.getColumnIndex('TEXT')),
          enable: resultSet.getLong(resultSet.getColumnIndex('ENABLE')) !== 0
        };
        rows.push(row);
      }
    } finally {
      resultSet.close();
    }
    return rows;
  }

  static async setEnabled(id: number, enable: boolean): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const values: relationalStore.ValuesBucket = { 'ENABLE': enable ? 1 : 0 };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('_id', id);
    return await store.update(values, predicates);
  }

  static async delete(id: number): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('_id', id);
    return await store.delete(predicates);
  }

  static async clear(): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    return await store.delete(predicates);
  }
}
