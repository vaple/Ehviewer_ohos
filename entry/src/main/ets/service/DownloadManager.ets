import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { PersistenceV2 } from '@kit.ArkUI';
import { Logger } from '../common/Logger';
import { DbHelper } from '../db/DbHelper';
import { DownloadDao } from '../db/dao/DownloadDao';
import { DownloadItem, DownloadPageRow, DownloadQuality, DownloadState } from '../model/DownloadRecord';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { GalleryPageResult } from '../parser/GalleryPageParser';
import { AppSettings } from '../state/AppSettings';
import { clampConcurrency, downloadSettings } from '../state/DownloadSettings';
import { detectImageExt } from './ImageExt';
import { DownloadBackground } from './DownloadBackground';
import { setDiagContext } from './CrashCollector';

const PREVIEW_PER_CHUNK: number = 20;
const RETRY_DELAYS: number[] = [1000, 3000, 10000];

/**
 * 画廊下载队列（单例）：逐页落盘到沙盒 `files/downloads/<gid>_<token>/`。
 *
 * - **不调用 `photoAccessHelper`**：下载内容不进系统相册（只有阅读器单页「保存」进相册）。
 * - 页级断点：已落盘页跳过；失败页重试 3 次（1s/3s/10s）后记失败，不阻塞其它页。
 * - 画廊级串行（一次一本），页级并发可配（`DownloadSettings.concurrency`，默认 2）。
 * - 后台保活（`backgroundTaskManager`）尚未接入：当前仅在应用存活期间下载；杀进程后重启自动续传。
 */
@ObservedV2
export class DownloadManager {
  /** 全部下载任务（DB 快照；`@Trace` 字段变化驱动 UI）。 */
  @Trace items: DownloadItem[] = [];
  /** 正在下载的 gid（-1 = 空闲）。 */
  @Trace activeGid: number = -1;

  private ctx: common.Context | undefined = undefined;
  private inited: boolean = false;
  private running: boolean = false;
  private stopRequested: Set<number> = new Set<number>();
  /** 每次 run 的序号：resume/remove 时递增，让旧的 run 收尾时直接退出、不覆盖新状态。 */
  private runIds: Map<number, number> = new Map<number, number>();
  private client: EhClient | null = null;
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  /** gid → 绝对页号 → 文件绝对路径（阅读器本地优先用）。 */
  private localFiles: Map<number, Map<number, string>> = new Map<number, Map<number, string>>();
  /** gid → 绝对页号 → pToken。 */
  private tokens: Map<number, string[]> = new Map<number, string[]>();
  private chunkLoading: Map<string, Promise<string[]>> = new Map<string, Promise<string[]>>();

  async init(context: common.Context): Promise<void> {
    if (this.inited) {
      return;
    }
    this.ctx = context;
    await DbHelper.init(context);
    this.inited = true;
    await this.reload();
    // 上次被杀进程时 RUNNING 的任务：恢复成排队并续传。
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state === DownloadState.RUNNING) {
        this.items[i].state = DownloadState.QUEUED;
      }
    }
    this.pump();
  }

  async reload(): Promise<void> {
    const rows: DownloadItem[] = await DownloadDao.queryAll();
    // 保留已有实例（@Trace 对象被 run 持有）：只把 DB 值写回同一个对象，避免 UI 与下载器各持一份。
    const existing: Map<number, DownloadItem> = new Map<number, DownloadItem>();
    for (let i = 0; i < this.items.length; i++) {
      existing.set(this.items[i].gid, this.items[i]);
    }
    const merged: DownloadItem[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row: DownloadItem = rows[i];
      const item: DownloadItem | undefined = existing.get(row.gid);
      if (item === undefined) {
        merged.push(row);
        continue;
      }
      item.token = row.token;
      item.title = row.title;
      item.category = row.category;
      item.pages = row.pages;
      item.quality = row.quality;
      item.state = row.state;
      item.donePages = row.donePages;
      item.failedPages = row.failedPages;
      item.bytes = row.bytes;
      item.dir = row.dir;
      item.thumb = row.thumb;
      item.thumbUrl = row.thumbUrl;
      item.createdAt = row.createdAt;
      item.updatedAt = row.updatedAt;
      merged.push(item);
    }
    this.items = merged;
  }

  itemOf(gid: number): DownloadItem | undefined {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid === gid) {
        return this.items[i];
      }
    }
    return undefined;
  }

  /** 阅读器优先用的本地文件 URI（没有则空串）。 */
  async localUri(gid: number, page: number): Promise<string> {
    if (!this.inited) {
      return '';
    }
    const path: string = await this.fileOf(gid, page);
    if (path.length === 0) {
      return '';
    }
    return fileUri.getUriFromPath(path);
  }

  /** 预加载某本画廊的「页 → 本地文件」映射（阅读器进页时调一次，之后翻页同步命中）。 */
  async prepareLocal(gid: number): Promise<void> {
    if (!this.inited) {
      return;
    }
    await this.ensureLocalMap(gid);
  }

  /** 同步取本地 URI（映射已加载时立即返回；未加载返回空串，调用方可走异步兜底）。 */
  localUriIfLoaded(gid: number, page: number): string {
    const map: Map<number, string> | undefined = this.localFiles.get(gid);
    if (map === undefined) {
      return '';
    }
    const path: string | undefined = map.get(page);
    return path === undefined ? '' : fileUri.getUriFromPath(path);
  }

  /** 入队并开始（同一 gid 重复调用会复用已有记录）。 */
  async start(gid: number, token: string, title: string, category: number, pages: number,
    quality: number, thumb: string, thumbUrl: string): Promise<void> {
    if (!this.inited) {
      throw new Error('download manager not initialized');
    }
    if (pages <= 0) {
      throw new Error('gallery has no pages');
    }
    let item: DownloadItem | undefined = this.itemOf(gid);
    if (item === undefined) {
      item = new DownloadItem(gid, token, title, category, pages);
      item.quality = quality;
      item.dir = `${gid}_${token}`;
      item.state = DownloadState.QUEUED;
      item.thumb = thumb;
      item.thumbUrl = thumbUrl;
      this.items = [item].concat(this.items);
    } else {
      item.token = token;
      item.title = title;
      item.category = category;
      item.pages = pages;
      item.quality = quality;
      item.state = DownloadState.QUEUED;
      item.message = '';
      item.failedPages = 0;
      if (thumb.length > 0) {
        item.thumb = thumb;
      }
      if (thumbUrl.length > 0) {
        item.thumbUrl = thumbUrl;
      }
      this.stopRequested.delete(gid);
    }
    await DownloadDao.upsert(item);
    this.pump();
  }

  async pause(gid: number): Promise<void> {
    const item: DownloadItem | undefined = this.itemOf(gid);
    Logger.info('Download', `pause requested gid=${gid} items=${this.items.length} found=${item !== undefined}`);
    this.stopRequested.add(gid);
    if (item !== undefined && item.state !== DownloadState.DONE) {
      item.state = DownloadState.PAUSED;
      Logger.info('Download', `pause set state=${item.state} gid=${gid}`);
      await DownloadDao.setState(gid, DownloadState.PAUSED);
      Logger.info('Download', `pause persisted gid=${gid}`);
    }
    await this.stopIfIdle();
  }

  async resume(gid: number): Promise<void> {
    const item: DownloadItem | undefined = this.itemOf(gid);
    Logger.info('Download', `resume requested gid=${gid} items=${this.items.length} found=${item !== undefined}`);
    this.stopRequested.delete(gid);
    if (item === undefined) {
      return;
    }
    // 递增 run 序号：旧的 run 收尾时看到序号变了会直接退出，不把状态改成 DONE/PAUSED。
    this.runIds.set(gid, (this.runIds.get(gid) ?? 0) + 1);
    item.state = DownloadState.QUEUED;
    await DownloadDao.setState(gid, DownloadState.QUEUED);
    Logger.info('Download', `resume queued gid=${gid} running=${this.running}`);
    this.pump();
  }

  async remove(gid: number, deleteFiles: boolean = true): Promise<void> {
    this.stopRequested.add(gid);
    this.runIds.set(gid, (this.runIds.get(gid) ?? 0) + 1);
    const item: DownloadItem | undefined = this.itemOf(gid);
    if (item !== undefined && deleteFiles) {
      try {
        fs.rmdirSync(this.dirOf(item));
      } catch (e) {
        Logger.error('Download', `remove dir failed gid=${gid}: ${e}`);
      }
    }
    await DownloadDao.delete(gid);
    this.localFiles.delete(gid);
    this.tokens.delete(gid);
    this.items = this.items.filter((it: DownloadItem) => it.gid !== gid);
    await this.stopIfIdle();
  }

  /** 没有排队/运行中的任务时，结束后台长时任务并撤掉进度通知。 */
  private async stopIfIdle(): Promise<void> {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state === DownloadState.QUEUED ||
        this.items[i].state === DownloadState.RUNNING) {
        return;
      }
    }
    await DownloadBackground.stop(this.ctx);
  }

  // ---------- 队列 ----------

  private async pump(): Promise<void> {
    if (this.running) {
      Logger.info('Download', `pump skipped (running) items=${this.items.length}`);
      return;
    }
    let next: DownloadItem | undefined = undefined;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state === DownloadState.QUEUED) {
        next = this.items[i];
        break;
      }
    }
    if (next === undefined) {
      Logger.info('Download', 'pump idle (no queued)');
      await this.stopIfIdle();
      return;
    }
    Logger.info('Download', `pump start gid=${next.gid}`);
    this.running = true;
    this.activeGid = next.gid;
    await DownloadBackground.start(this.ctx);
    await DownloadBackground.notify(next.title, next.donePages, next.pages);
    try {
      await this.run(next);
    } catch (e) {
      Logger.error('Download', `run failed gid=${next.gid}: ${e}`);
      next.state = DownloadState.FAILED;
      next.message = '下载失败，请重试';
      await DownloadDao.setState(next.gid, DownloadState.FAILED);
    } finally {
      this.running = false;
      this.activeGid = -1;
    }
    // 还有排队任务就继续（串行）。
    this.pump();
  }

  private async run(item: DownloadItem): Promise<void> {
    setDiagContext(`page=download gid=${item.gid}`);
    const runId: number = (this.runIds.get(item.gid) ?? 0) + 1;
    this.runIds.set(item.gid, runId);
    item.state = DownloadState.RUNNING;
    item.message = '';
    await DownloadDao.setState(item.gid, DownloadState.RUNNING);
    await this.ensureLocalMap(item.gid);
    const dir: string = this.dirOf(item);
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }

    const concurrency: number = clampConcurrency(downloadSettings().concurrency);
    let nextPage: number = 0;
    let failed: number = 0;
    let completed: number = 0;

    const worker = async (): Promise<void> => {
      while (nextPage < item.pages) {
        if (this.stopRequested.has(item.gid)) {
          return;
        }
        const page: number = nextPage;
        nextPage += 1;
        if (await this.fileOf(item.gid, page) !== '') {
          continue;
        }
        let ok: boolean = false;
        for (let attempt = 0; attempt <= RETRY_DELAYS.length && !ok; attempt++) {
          if (this.stopRequested.has(item.gid)) {
            return;
          }
          try {
            const bytes: number = await this.fetchPage(item, page);
            completed += 1;
            item.donePages = Math.min(item.pages, item.donePages + 1);
            item.bytes += bytes;
            await DownloadDao.setProgress(item.gid, item.donePages, item.bytes);
            // 每页都刷新通知（节流由网络本身决定）；暂停/删完后不再发。
            if (!this.stopRequested.has(item.gid)) {
              await DownloadBackground.notify(item.title, item.donePages, item.pages);
            }
            ok = true;
          } catch (e) {
            Logger.error('Download', `gid=${item.gid} page=${page + 1} attempt=${attempt}: ${e}`);
            if (attempt < RETRY_DELAYS.length) {
              await DownloadManager.sleep(RETRY_DELAYS[attempt]);
            }
          }
        }
        if (!ok) {
          failed += 1;
          item.failedPages = failed;
        }
      }
    };

    const workers: Promise<void>[] = [];
    for (let i = 0; i < concurrency; i++) {
      workers.push(worker());
    }
    await Promise.all(workers);

    // 被 resume/remove 换代：直接退出，状态由新的一轮接管。
    if (this.runIds.get(item.gid) !== runId) {
      return;
    }
    // 被暂停：`pause()` 已经把状态写成 PAUSED，收尾不要覆盖。
    if (this.stopRequested.has(item.gid)) {
      return;
    }
    if (failed > 0) {
      item.state = DownloadState.FAILED;
      item.message = `${failed} 页失败，点重试`;
      await DownloadDao.setState(item.gid, DownloadState.FAILED);
      await this.stopIfIdle();
    } else {
      item.state = DownloadState.DONE;
      item.message = '';
      item.donePages = item.pages;
      await DownloadDao.setState(item.gid, DownloadState.DONE);
      await this.stopIfIdle();
    }
    Logger.info('Download', `gid=${item.gid} finished state=${item.state} pages=${completed}/${item.pages}`);
  }

  /** 下载一页并落盘，返回字节数。 */
  private async fetchPage(item: DownloadItem, page: number): Promise<number> {
    const client: EhClient = await this.ensureClient();
    const site: EhSite = this.settings.site;
    const token: string = await this.tokenFor(item, page);
    if (token.length === 0) {
      throw new Error(`missing pToken for page ${page + 1}`);
    }
    const pageUrl: string = EhUrl.galleryPage(site, item.gid, page + 1, token);
    const result: GalleryPageResult =
      await client.getGalleryPage(site, item.gid, page + 1, token);
    const url: string = item.quality === DownloadQuality.ORIGINAL && result.originalUrl !== null
      ? result.originalUrl
      : result.imageUrl;
    const buf: ArrayBuffer = await client.getImageBytes(url, pageUrl);
    const ext: string = detectImageExt(new Uint8Array(buf));
    const name: string = `${DownloadManager.pad(page + 1)}.${ext}`;
    const path: string = `${this.dirOf(item)}/${name}`;
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, buf);
    } finally {
      fs.closeSync(file);
    }
    const row: DownloadPageRow = {
      gid: item.gid,
      page: page,
      file: name,
      bytes: buf.byteLength,
      state: 2
    };
    await DownloadDao.putPage(row);
    this.mapOf(item.gid).set(page, path);
    return buf.byteLength;
  }

  // ---------- 工具 ----------

  private async ensureClient(): Promise<EhClient> {
    if (this.client !== null) {
      return this.client;
    }
    if (this.ctx === undefined) {
      throw new Error('download manager context missing');
    }
    const cookies: CookieStore = new CookieStore();
    await cookies.init(this.ctx);
    this.client = new EhClient(new RcpHttpClient(), cookies);
    return this.client;
  }

  /** 绝对页号 → pToken（按 20 页一个预览分块懒加载，并发安全）。 */
  private async tokenFor(item: DownloadItem, page: number): Promise<string> {
    let arr: string[] | undefined = this.tokens.get(item.gid);
    if (arr === undefined) {
      arr = [];
      this.tokens.set(item.gid, arr);
    }
    if (arr[page] !== undefined) {
      return arr[page];
    }
    const chunk: number = Math.floor(page / PREVIEW_PER_CHUNK);
    const key: string = `${item.gid}:${chunk}`;
    let loading: Promise<string[]> | undefined = this.chunkLoading.get(key);
    if (loading === undefined) {
      const client: EhClient = await this.ensureClient();
      loading = client.getPreviewTokens(this.settings.site, item.gid, item.token, chunk);
      this.chunkLoading.set(key, loading);
    }
    const pending: Promise<string[]> = loading !== undefined
      ? loading
      : Promise.resolve<string[]>([]);
    const fetched: string[] = await pending;
    for (let i = 0; i < fetched.length; i++) {
      if (fetched[i] !== undefined && arr[i] === undefined) {
        arr[i] = fetched[i];
      }
    }
    this.chunkLoading.delete(key);
    return arr[page] !== undefined ? arr[page] : '';
  }

  private dirOf(item: DownloadItem): string {
    if (this.ctx === undefined) {
      throw new Error('download manager context missing');
    }
    return `${this.ctx.filesDir}/downloads/${item.dir}`;
  }

  private mapOf(gid: number): Map<number, string> {
    let map: Map<number, string> | undefined = this.localFiles.get(gid);
    if (map === undefined) {
      map = new Map<number, string>();
      this.localFiles.set(gid, map);
    }
    return map;
  }

  private async ensureLocalMap(gid: number): Promise<void> {
    const map: Map<number, string> = this.mapOf(gid);
    if (map.size > 0) {
      return;
    }
    const item: DownloadItem | undefined = this.itemOf(gid);
    if (item === undefined) {
      return;
    }
    const rows: DownloadPageRow[] = await DownloadDao.queryPages(gid);
    for (let i = 0; i < rows.length; i++) {
      map.set(rows[i].page, `${this.dirOf(item)}/${rows[i].file}`);
    }
  }

  private async fileOf(gid: number, page: number): Promise<string> {
    await this.ensureLocalMap(gid);
    const path: string | undefined = this.mapOf(gid).get(page);
    if (path === undefined) {
      return '';
    }
    try {
      if (fs.accessSync(path)) {
        return path;
      }
      this.mapOf(gid).delete(page);
      return '';
    } catch (e) {
      this.mapOf(gid).delete(page);
      return '';
    }
  }

  private static pad(n: number): string {
    return n < 10 ? `00${n}` : (n < 100 ? `0${n}` : `${n}`);
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}

/** 全局单例（页面直接引用；`@Trace` 字段驱动刷新）。 */
export const downloadManager: DownloadManager = new DownloadManager();
