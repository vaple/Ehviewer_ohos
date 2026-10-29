import { relationalStore } from '@kit.ArkData';
import { HistoryInfo } from '../../model/HistoryInfo';
import { DbHelper } from '../DbHelper';

const TABLE: string = 'HISTORY';
const COLUMNS: string = 'GID,TOKEN,TITLE,TITLE_JPN,THUMB,CATEGORY,POSTED,UPLOADER,RATING,SIMPLE_LANGUAGE,MODE,TIME';

/** `HISTORY` 表的 DAO（`GID` 为业务主键）。 */
export class HistoryDao {
  static async put(info: HistoryInfo): Promise<void> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const args: relationalStore.ValueType[] = [
      info.gid, info.token, info.title, info.titleJpn, info.thumb, info.category,
      info.posted, info.uploader, info.rating, info.simpleLanguage, info.mode, info.time
    ];
    await store.executeSql(
      `INSERT OR REPLACE INTO ${TABLE} (${COLUMNS}) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`, args);
  }

  static async queryAll(): Promise<HistoryInfo[]> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const resultSet: relationalStore.ResultSet =
      await store.querySql(`SELECT ${COLUMNS} FROM ${TABLE} ORDER BY TIME DESC`);
    const rows: HistoryInfo[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const row: HistoryInfo = {
          gid: resultSet.getLong(resultSet.getColumnIndex('GID')),
          token: resultSet.getString(resultSet.getColumnIndex('TOKEN')),
          title: resultSet.getString(resultSet.getColumnIndex('TITLE')),
          titleJpn: resultSet.getString(resultSet.getColumnIndex('TITLE_JPN')),
          thumb: resultSet.getString(resultSet.getColumnIndex('THUMB')),
          category: resultSet.getLong(resultSet.getColumnIndex('CATEGORY')),
          posted: resultSet.getString(resultSet.getColumnIndex('POSTED')),
          uploader: resultSet.getString(resultSet.getColumnIndex('UPLOADER')),
          rating: resultSet.getDouble(resultSet.getColumnIndex('RATING')),
          simpleLanguage: resultSet.getString(resultSet.getColumnIndex('SIMPLE_LANGUAGE')),
          pages: 0,
          mode: resultSet.getLong(resultSet.getColumnIndex('MODE')),
          time: resultSet.getLong(resultSet.getColumnIndex('TIME'))
        };
        rows.push(row);
      }
    } finally {
      resultSet.close();
    }
    return rows;
  }

  static async delete(gid: number): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('GID', gid);
    return await store.delete(predicates);
  }

  /** 仅保留最新 `max` 条（按 TIME 降序）。 */
  static async trimTo(max: number): Promise<void> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const args: relationalStore.ValueType[] = [max];
    await store.executeSql(
      `DELETE FROM ${TABLE} WHERE GID NOT IN (SELECT GID FROM ${TABLE} ORDER BY TIME DESC LIMIT ?)`, args);
  }

  static async clear(): Promise<number> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    return await store.delete(predicates);
  }
}
