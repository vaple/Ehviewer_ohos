/** 下载状态（与 DB 数值一致）。 */
export enum DownloadState {
  QUEUED = 0,
  RUNNING = 1,
  PAUSED = 2,
  DONE = 3,
  FAILED = 4
}

/** 下载画质：原图（`fullimg`）/ 站点当前尺寸（`#img`）。 */
export enum DownloadQuality {
  ORIGINAL = 0,
  SITE = 1
}

/** 一条下载（DB 行 → UI 可观察对象）。 */
@ObservedV2
export class DownloadItem {
  gid: number = 0;
  @Trace token: string = '';
  @Trace title: string = '';
  @Trace category: number = -1;
  @Trace pages: number = 0;
  @Trace quality: number = DownloadQuality.ORIGINAL;
  @Trace state: number = DownloadState.QUEUED;
  @Trace donePages: number = 0;
  @Trace failedPages: number = 0;
  @Trace bytes: number = 0;
  @Trace dir: string = '';
  @Trace thumb: string = '';
  @Trace thumbUrl: string = '';
  @Trace message: string = '';
  createdAt: number = 0;
  @Trace updatedAt: number = 0;

  constructor(gid: number, token: string, title: string, category: number, pages: number) {
    this.gid = gid;
    this.token = token;
    this.title = title;
    this.category = category;
    this.pages = pages;
  }
}

/** 单页下载记录（断点 / 失败重试用）。 */
export interface DownloadPageRow {
  gid: number;
  page: number;
  file: string;
  bytes: number;
  state: number;
}
