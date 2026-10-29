import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SessionState } from '../state/SessionState';
import { DiagLog } from '../service/DiagLog';
import { CrashCollector } from '../service/CrashCollector';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 日志要尽早可用：崩溃/网络日志都是从这里之后才可能发生的。
    DiagLog.init(`${this.context.filesDir}/logs`);
    // 崩溃订阅必须在业务之前（官方要求），否则可能漏掉本次启动后的崩溃事件。
    CrashCollector.install();
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    DiagLog.flush();
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'EntryAbility', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      // 全屏布局（窗口级）：页面根铺到 y=0，系统栏仍显示，由各页 HDS 标题栏避让。
      windowStage.getMainWindowSync().setWindowLayoutFullScreen(true).catch((e: object) => {
        hilog.error(DOMAIN, 'EntryAbility', 'Failed to set fullscreen. Cause: %{public}s', JSON.stringify(e));
      });
      hilog.info(DOMAIN, 'EntryAbility', 'Succeeded in loading the content.');
    });
    this.syncWindowBackground();

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'EntryAbility', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 窗口底色 = 页面底色（状态栏/导航栏区域由窗口背景填充）。
   * 不设的话浅色下状态栏是窗口白、页面是灰底，中间一道分界；深色下同理。
   */
  private syncWindowBackground(): void {
    try {
      const argb: number = this.context.resourceManager.getColorSync($r('app.color.bg_primary').id);
      const hex: string = `#${(argb >>> 0).toString(16).padStart(8, '0')}`;
      window.getLastWindow(this.context).then((win: window.Window) => {
        win.setWindowBackgroundColor(hex);
      }).catch((err: object) => {
        hilog.error(DOMAIN, 'EntryAbility', 'Failed to set window background. Cause: %{public}s',
          JSON.stringify(err));
      });
    } catch (err) {
      hilog.error(DOMAIN, 'EntryAbility', 'Failed to resolve page background. Cause: %{public}s',
        JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onForeground');
  }

  /** 退到后台就把缓冲刷盘：用户从最近任务划掉进程时，不会再给我们 flush 的机会。 */
  onBackground(): void {
    DiagLog.flush();
    // Ability has back to background
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onBackground');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 系统配置变化（深浅切换等）→ 递增内存版本号，订阅方（`AppShell`）重算主题相关快照。
    try {
      const session: SessionState | undefined =
        AppStorageV2.connect(SessionState, () => new SessionState());
      if (session) {
        session.configVersion += 1;
      }
    } catch (err) {
      hilog.error(DOMAIN, 'EntryAbility', 'Failed to bump config version. Cause: %{public}s', JSON.stringify(err));
    }
    // 深浅变了，窗口底色（状态栏区域）也要跟着变。
    this.syncWindowBackground();
  }
}