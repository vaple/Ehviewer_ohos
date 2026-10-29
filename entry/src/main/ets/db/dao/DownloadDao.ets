import { relationalStore } from '@kit.ArkData';
import {
  DownloadItem,
  DownloadPageRow,
  DownloadQuality,
  DownloadState
} from '../../model/DownloadRecord';
import { DbHelper } from '../DbHelper';

const TABLE: string = 'DOWNLOAD';
const PAGE_TABLE: string = 'DOWNLOAD_PAGE';
const COLUMNS: string = 'GID,TOKEN,TITLE,CATEGORY,PAGES,QUALITY,STATE,DONE_PAGES,FAILED_PAGES,BYTES,' +
  'CREATED_AT,UPDATED_AT,DIR,THUMB,THUMB_URL';

function toItem(rs: relationalStore.ResultSet): DownloadItem {
  const gid: number = rs.getLong(rs.getColumnIndex('GID'));
  const item: DownloadItem = new DownloadItem(
    gid,
    rs.getString(rs.getColumnIndex('TOKEN')),
    rs.getString(rs.getColumnIndex('TITLE')),
    rs.getLong(rs.getColumnIndex('CATEGORY')),
    rs.getLong(rs.getColumnIndex('PAGES'))
  );
  item.quality = rs.getLong(rs.getColumnIndex('QUALITY'));
  item.state = rs.getLong(rs.getColumnIndex('STATE'));
  item.donePages = rs.getLong(rs.getColumnIndex('DONE_PAGES'));
  item.failedPages = rs.getLong(rs.getColumnIndex('FAILED_PAGES'));
  item.bytes = rs.getLong(rs.getColumnIndex('BYTES'));
  item.createdAt = rs.getLong(rs.getColumnIndex('CREATED_AT'));
  item.updatedAt = rs.getLong(rs.getColumnIndex('UPDATED_AT'));
  item.dir = rs.getString(rs.getColumnIndex('DIR'));
  item.thumb = rs.getString(rs.getColumnIndex('THUMB'));
  item.thumbUrl = rs.getString(rs.getColumnIndex('THUMB_URL'));
  return item;
}

/** `DOWNLOAD` / `DOWNLOAD_PAGE` 两张表的 DAO（`GID` 为业务主键）。 */
export class DownloadDao {
  static async queryAll(): Promise<DownloadItem[]> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const rs: relationalStore.ResultSet = await store.querySql(
      `SELECT ${COLUMNS} FROM ${TABLE} ORDER BY UPDATED_AT DESC`);
    const rows: DownloadItem[] = [];
    try {
      while (rs.goToNextRow()) {
        rows.push(toItem(rs));
      }
    } finally {
      rs.close();
    }
    return rows;
  }

  static async get(gid: number): Promise<DownloadItem | null> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const rs: relationalStore.ResultSet = await store.querySql(
      `SELECT ${COLUMNS} FROM ${TABLE} WHERE GID = ?`, [gid]);
    try {
      if (!rs.goToNextRow()) {
        return null;
      }
      return toItem(rs);
    } finally {
      rs.close();
    }
  }

  static async upsert(item: DownloadItem): Promise<void> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const now: number = Date.now();
    if (item.createdAt === 0) {
      item.createdAt = now;
    }
    item.updatedAt = now;
    const args: relationalStore.ValueType[] = [
      item.gid, item.token, item.title, item.category, item.pages, item.quality, item.state,
      item.donePages, item.failedPages, item.bytes, item.createdAt, item.updatedAt, item.dir,
      item.thumb, item.thumbUrl
    ];
    await store.executeSql(
      `INSERT OR REPLACE INTO ${TABLE} (${COLUMNS}) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`, args);
  }

  static async setThumb(gid: number, thumb: string): Promise<void> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    await store.executeSql(
      `UPDATE ${TABLE} SET THUMB = ? WHERE GID = ?`, [thumb, gid]);
  }

  static async setState(gid: number, state: number): Promise<void> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    await store.executeSql(
      `UPDATE ${TABLE} SET STATE = ?, UPDATED_AT = ? WHERE GID = ?`,
      [state, Date.now(), gid]);
  }

  static async setProgress(gid: number, donePages: number, bytes: number): Promise<void> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    await store.executeSql(
      `UPDATE ${TABLE} SET DONE_PAGES = ?, BYTES = ?, UPDATED_AT = ? WHERE GID = ?`,
      [donePages, bytes, Date.now(), gid]);
  }

  static async delete(gid: number): Promise<void> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    await store.executeSql(`DELETE FROM ${PAGE_TABLE} WHERE GID = ?`, [gid]);
    await store.executeSql(`DELETE FROM ${TABLE} WHERE GID = ?`, [gid]);
  }

  static async putPage(row: DownloadPageRow): Promise<void> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    await store.executeSql(
      `INSERT OR REPLACE INTO ${PAGE_TABLE} (GID,PAGE,FILE,BYTES,STATE) VALUES (?,?,?,?,?)`,
      [row.gid, row.page, row.file, row.bytes, row.state]);
  }

  static async queryPages(gid: number): Promise<DownloadPageRow[]> {
    const store: relationalStore.RdbStore = DbHelper.getStore();
    const rs: relationalStore.ResultSet = await store.querySql(
      `SELECT GID,PAGE,FILE,BYTES,STATE FROM ${PAGE_TABLE} WHERE GID = ? ORDER BY PAGE`, [gid]);
    const rows: DownloadPageRow[] = [];
    try {
      while (rs.goToNextRow()) {
        rows.push({
          gid: rs.getLong(rs.getColumnIndex('GID')),
          page: rs.getLong(rs.getColumnIndex('PAGE')),
          file: rs.getString(rs.getColumnIndex('FILE')),
          bytes: rs.getLong(rs.getColumnIndex('BYTES')),
          state: rs.getLong(rs.getColumnIndex('STATE'))
        });
      }
    } finally {
      rs.close();
    }
    return rows;
  }

  /** 仅用于 UI：画质/状态文案映射（纯函数，Local 单测覆盖）。 */
  static qualityLabel(quality: number): string {
    return quality === DownloadQuality.SITE ? '站点尺寸' : '原图';
  }

  static stateLabel(state: number): string {
    if (state === DownloadState.RUNNING) {
      return '下载中';
    }
    if (state === DownloadState.PAUSED) {
      return '已暂停';
    }
    if (state === DownloadState.DONE) {
      return '已完成';
    }
    if (state === DownloadState.FAILED) {
      return '下载失败';
    }
    return '排队中';
  }
}
