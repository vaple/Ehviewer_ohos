import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { Logger } from '../common/Logger';
import { HttpClient } from '../network/HttpClient';
import { ReleaseClient, ReleaseInfo, ReleasePick, ReleaseSource } from '../network/ReleaseClient';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { UpdateState, downloadUrlOf, updateState } from '../state/UpdateState';

/** `pickAndStart` 的结果（调用方据此给不同文案；取消不当作错误）。 */
export enum DownloadStart {
  STARTED = 0,
  CANCELLED = 1,
  FAILED = 2,
  NO_URL = 3
}

/** 从择优结果里按源取下载地址（该源不在 `mirrors` 里 → 空串）。 */
function urlFor(pick: ReleasePick, source: ReleaseSource): string {
  for (let i: number = 0; i < pick.mirrors.length; i++) {
    const info: ReleaseInfo = pick.mirrors[i];
    if (info.source === source) {
      return info.hapUrl;
    }
  }
  return '';
}

/**
 * 下载任务的配置。
 *
 * **`saveas` 是 `DocumentViewPicker.save()` 给的 uri 时必须用 `Mode.FOREGROUND`**：
 * picker 的 uri 授权只给应用进程，`Mode.BACKGROUND` 的传输在下载服务进程里跑、拿不到这个授权
 * （官方「应用文件上传下载」指南里这一段的注释原文就是「mode字段必须为request.agent.Mode.FOREGROUND」）。
 * 代价：传输跟随应用生命周期，退到后台/杀进程可能中断——对 <1MB 的 hap 可接受。
 */
export function buildDownloadConfig(url: string, uri: string): request.agent.Config {
  const config: request.agent.Config = {
    action: request.agent.Action.DOWNLOAD,
    url: url,
    saveas: uri,
    overwrite: true,
    mode: request.agent.Mode.FOREGROUND,
    gauge: true,
    network: request.agent.Network.ANY,
    notification: {
      visibility: request.agent.VISIBILITY_PROGRESS | request.agent.VISIBILITY_COMPLETION
    }
  };
  return config;
}

/**
 * 更新检查编排 + 建下载任务。
 *
 * - `check()`：并行问两个源 → 择优 → 逐属性写 `UpdateState`；**永不抛**，失败只把 `lastCheckOk` 置 false
 *   （不抹掉已知的 `latest*` 字段，否则一次网络失败会让红点意外消失）。
 * - `startDownload()`：只负责把下载交给系统下载服务（`request.agent`），传输 / 进度通知 / 失败收尾都在系统侧；
 *   App 不读文件、不校验、不保活、不自发通知。
 */
export class UpdateManager {
  /** `http` 只为单测注入；生产调用不传。 */
  static async check(http?: HttpClient): Promise<boolean> {
    const client: ReleaseClient = new ReleaseClient(http === undefined ? new RcpHttpClient() : http);
    const pick: ReleasePick | undefined = await client.latest();
    const state: UpdateState = updateState();
    if (pick === undefined) {
      state.lastCheckOk = false;
      Logger.error('Update', 'check failed: both sources unavailable');
      return false;
    }
    state.lastCheckOk = true;
    state.lastCheckAtMs = Date.now();
    state.latestTag = pick.chosen.tag;
    state.latestVersion = pick.chosen.version;
    state.notes = pick.chosen.notes;
    state.hapName = pick.chosen.hapName;
    state.gitcodeUrl = urlFor(pick, ReleaseSource.GITCODE);
    state.githubUrl = urlFor(pick, ReleaseSource.GITHUB);
    Logger.info('Update', `check ok: ${pick.chosen.tag} mirrors=${pick.mirrors.length}`);
    return true;
  }

  /**
   * 弹系统保存面板（默认文件名取 release 资产名）→ 把下载交给系统下载服务。
   * 用户取消面板 → `CANCELLED`（调用方不该报错）；没有下载地址 → `NO_URL`（记日志）。
   */
  static async pickAndStart(ctx: common.Context): Promise<DownloadStart> {
    const state: UpdateState = updateState();
    const url: string = downloadUrlOf(state);
    if (url.length === 0) {
      Logger.error('Update', 'download skipped: no url in state');
      return DownloadStart.NO_URL;
    }
    let uri: string = '';
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [state.hapName];
      const savePicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const uris: string[] = await savePicker.save(options);
      uri = uris.length === 0 ? '' : uris[0];
    } catch (e) {
      Logger.error('Update', `save panel failed: ${e}`);
      return DownloadStart.FAILED;
    }
    if (uri.length === 0) {
      return DownloadStart.CANCELLED;
    }
    try {
      await UpdateManager.startDownload(ctx, url, uri);
      return DownloadStart.STARTED;
    } catch (e) {
      Logger.error('Update', `start download failed: ${e}`);
      return DownloadStart.FAILED;
    }
  }

  /**
   * 交给系统下载服务写入用户选定的 uri（`saveas` 来自 `DocumentViewPicker.save()`）。
   * 进度通知由系统发；这里只挂日志事件，做完不做任何后续处理。
   */
  static async startDownload(ctx: common.Context, url: string, uri: string): Promise<void> {
    const task: request.agent.Task = await request.agent.create(ctx, buildDownloadConfig(url, uri));
    task.on('completed', () => {
      Logger.info('Update', `hap download completed: ${uri}`);
      // 官方示例：完成即移除任务对象，否则下载服务里会一直积压已完成任务。
      request.agent.remove(task.tid).catch((e: object) => {
        Logger.error('Update', `remove download task failed: ${e}`);
      });
    });
    task.on('failed', (progress: request.agent.Progress) => {
      Logger.error('Update', `hap download failed: ${JSON.stringify(progress)}`);
    });
    await task.start();
  }
}
