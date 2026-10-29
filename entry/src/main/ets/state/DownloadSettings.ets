import { PersistenceV2 } from '@kit.ArkUI';

/** 下载设置（独立 key：改这里不会重置 `AppSettings`）。 */
@ObservedV2
export class DownloadSettings {
  /** 同时下载的页数（1–4；越大越快，也越容易触发站点限流）。 */
  @Trace concurrency: number = 2;
}

/** 收敛到 1–4（越界回落默认 2）。 */
export function clampConcurrency(n: number): number {
  if (isNaN(n) || n < 1 || n > 4) {
    return 2;
  }
  return Math.floor(n);
}

/** 全局连接（应用级持久化）。 */
export function downloadSettings(): DownloadSettings {
  return PersistenceV2.globalConnect({
    type: DownloadSettings,
    key: 'DownloadSettings1',
    defaultCreator: () => new DownloadSettings()
  })!;
}
