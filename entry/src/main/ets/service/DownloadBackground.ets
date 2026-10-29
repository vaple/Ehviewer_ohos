import { common } from '@kit.AbilityKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { Logger } from '../common/Logger';

const NOTIFY_ID: number = 1001;
const BUNDLE: string = 'io.github.vaple.ehviewer';
const ABILITY: string = 'EntryAbility';

/**
 * 下载的后台长时任务 + 进度通知（官方 `backgroundTaskManager` DATA_TRANSFER）。
 *
 * - 需要 `module.json5`：`ohos.permission.KEEP_BACKGROUND_RUNNING` + ability `backgroundModes: ["dataTransfer"]`。
 * - 长时任务本身会带一条系统通知；这里额外 publish 自己的进度通知（同 id 覆盖更新），
 *   用户不开通知权限时只记日志，不影响下载。
 * - 失败不抛给下载队列（下载仍可前台继续），只记日志。
 */
export class DownloadBackground {
  private static running: boolean = false;

  static async start(context: common.Context | undefined): Promise<void> {
    if (DownloadBackground.running || context === undefined) {
      return;
    }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: BUNDLE, abilityName: ABILITY }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(
        context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      DownloadBackground.running = true;
      await DownloadBackground.ensureNotifications(context);
    } catch (e) {
      Logger.error('Download', `start background task failed: ${e}`);
    }
  }

  /** 首次下载时请求一次通知授权（拒绝也不影响下载，只记日志）。 */
  private static async ensureNotifications(context: common.Context): Promise<void> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        await notificationManager.requestEnableNotification(context as common.UIAbilityContext);
      }
    } catch (e) {
      Logger.error('Download', `request notification permission failed: ${e}`);
    }
  }

  static async stop(context: common.Context | undefined): Promise<void> {
    if (!DownloadBackground.running) {
      return;
    }
    DownloadBackground.running = false;
    if (context !== undefined) {
      try {
        await backgroundTaskManager.stopBackgroundRunning(context);
      } catch (e) {
        Logger.error('Download', `stop background task failed: ${e}`);
      }
    }
    try {
      await notificationManager.cancel(NOTIFY_ID);
    } catch (e) {
      Logger.error('Download', `cancel notification failed: ${e}`);
    }
  }

  /** 更新进度通知（同 id 覆盖；失败只记日志）。 */
  static async notify(title: string, done: number, total: number): Promise<void> {
    // 任务已结束/暂停后，迟到的图片完成不应把通知又发回来。
    if (!DownloadBackground.running) {
      return;
    }
    try {
      const request: notificationManager.NotificationRequest = {
        id: NOTIFY_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '正在下载',
            text: `${done} / ${total} 页`,
            additionalText: title
          }
        }
      };
      await notificationManager.publish(request);
    } catch (e) {
      Logger.error('Download', `publish notification failed: ${e}`);
    }
  }
}
