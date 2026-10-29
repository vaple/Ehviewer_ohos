import { common } from '@kit.AbilityKit';
import { PersistenceV2 } from '@kit.ArkUI';
import { AppSettings } from '../state/AppSettings';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { HomeStats } from '../model/HomeStats';
import { Logger } from '../common/Logger';

/**
 * 下载半模态里的图片配额行（`home.php` → Image Limits）。
 *
 * 独立组件：`bindSheet` 的 builder 只在打开时构建一次，但子组件自己的 `@Local` 更新仍会重绘，
 * 所以可以先弹 sheet、再异步取配额（不卡打开）。
 *
 * 显示规则：
 * - 账号额度：`剩余配额 X / Y`
 * - IP 计额度：`按 IP 计图片配额`
 * - 未登录 / 读取失败：不显示（不拿错误占地方）
 */
@ComponentV2
export struct QuotaLine {
  @Local text: string = '';
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;

  aboutToAppear(): void {
    this.load();
  }

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private async load(): Promise<void> {
    try {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      const stats: HomeStats = await client.getHomeStats(this.settings.site);
      if (!stats.ok) {
        return;
      }
      if (stats.ipBased) {
        this.text = '按 IP 计图片配额';
        return;
      }
      const left: number = Math.max(0, stats.total - stats.used);
      this.text = `剩余配额 ${left} / ${stats.total}`;
    } catch (e) {
      Logger.error('Download', `quota line failed: ${e}`);
    }
  }

  build() {
    if (this.text.length > 0) {
      Text(this.text)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
  }
}
