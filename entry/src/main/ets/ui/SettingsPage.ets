import { common, Want } from '@kit.AbilityKit';
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { webview } from '@kit.ArkWeb';
import { AppStorageV2, PersistenceV2, promptAction, SubHeaderV2, SubHeaderV2Title } from '@kit.ArkUI';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { parseCookieString } from '../parser/CookieStringParser';
import { Logger } from '../common/Logger';
import { AppSettings, displayModeToColorMode } from '../state/AppSettings';
import { SessionState } from '../state/SessionState';
import { WindowState } from '../state/WindowState';
import { DownloadSettings, downloadSettings, clampConcurrency } from '../state/DownloadSettings';
import { HdsListItemCard, HdsNavDestination, PrefixIcon, SuffixArrow, SuffixBadgeAndArrow, SuffixButton, SuffixSelect } from '@kit.UIDesignKit';
import { CARD_GAP, CARD_RADIUS, PAGE_PADDING, SHEET_MATERIAL } from './Materials';
import { TITLE_BAR_H } from './NavStyle';
import { CacheManager } from '../service/CacheManager';
import { formatBytes } from '../common/Bytes';
import { DiagLog, statsSummary } from '../service/DiagLog';
import { ExportMeta, LogExport } from '../service/LogExport';
import { VERSION_NAME } from 'BuildProfile';
import { clampPrefetch, PREFETCH_MAX, PREFETCH_MIN } from '../reader/PrefetchPlan';
import { navTitleBarStyle } from './NavStyle';
import { UpdateState, hasUpdate, updateState, updateSummary } from '../state/UpdateState';
import { DownloadStart, UpdateManager } from '../service/UpdateManager';

const LOGIN_URL: string = 'https://forums.e-hentai.org/index.php?act=Login';

/** 应用版本名（来自构建产物 `BuildProfile`，发版自动同步，不再手工维护）。 */
const APP_VERSION_NAME: string = VERSION_NAME;

/** 缩略图尺寸档（值对照源 `Settings.getThumbResolution`：0 原图 / 1 `_250` / 2 `_300`）。 */
interface ThumbSizeOption {
  label: string;
  value: number;
}

const THUMB_SIZE_OPTIONS: ThumbSizeOption[] = [
  { label: '原图', value: 0 },
  { label: '中 (250)', value: 1 },
  { label: '大 (300)', value: 2 }
];

/** `SuffixSelect` 用的纯文本选项：从 `THUMB_SIZE_OPTIONS` 派生（单一来源，避免文案漂移）。 */
const THUMB_SIZE_LABELS: string[] = THUMB_SIZE_OPTIONS.map((o: ThumbSizeOption) => o.label);

/** 显示模式选项（下标即 `AppSettings.displayMode`：0 跟随系统 / 1 浅色 / 2 深色）。 */
const DISPLAY_MODE_LABELS: string[] = ['跟随系统', '浅色', '深色'];

/** 通用输入行：父组件用 `!!` 双向绑定（`@Param value` + `@Event $value`）。 */
@ComponentV2
struct LoginField {
  @Require @Param label: string;
  @Require @Param value: string;
  @Param isPassword: boolean = false;
  @Event $value: (v: string) => void = (_v: string) => {};

  build() {
    Row() {
      Text(this.label).fontSize(14).width(120).fontColor($r('app.color.text_secondary'))
      TextInput({ text: this.value })
        .type(this.isPassword ? InputType.Password : InputType.Normal)
        .layoutWeight(1)
        .onChange((v: string) => this.$value(v))
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }
}

/**
 * 设置页：站点 + 显示 + 语言 + 登录（Web / 手动 Cookie）+ 下载 + 高级。
 * 无账号密码表单：直登 POST 被 Cloudflare 拦截（永远 403，人话见下方说明），只留走得通的两路。
 */
@ComponentV2
export struct SettingsPage {
  @Local settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  @Local ipbMemberId: string = '';
  @Local ipbPassHash: string = '';
  @Local igneous: string = '';
  /** 站端展示偏好（`uconfig` cookie 形态；Web 同步专用，无手动输入框）。 */
  @Local uconfig: string = '';
  @Local message: string = '';
  @Local showWeb: boolean = false;
  /** 缓存占用（字节格式化后的展示串；`—` = 尚未统计）。 */
  @Local cacheText: string = '—';
  @Local cacheBusy: boolean = false;
  /** Cookie 导入草稿（半模态里的输入框；导出直接进剪贴板，不在页面常驻文本框）。 */
  @Local cookieDraft: string = '';
  /** 半模态：`sheetKind` 1 = 导入 Cookie / 2 = 诊断日志（一个节点只能挂一个 `bindSheet`）。 */
  @Local sheetOpen: boolean = false;
  @Local sheetKind: number = 0;
  /** 诊断日志副标题（打开半模态前先算好：`bindSheet` 打开后改状态不会重绘）。 */
  @Local diagText: string = '—';
  /** 打包中（防重复点击）。 */
  @Local diagBusy: boolean = false;
  /** 站端页 URL（`''` = 关；UConfig/我的标签共用 Web 壳，进页前种 Cookie、出页写回）。 */
  @Local sitePageUrl: string = '';
  private pageStack: NavPathStack | undefined = undefined;
  private controller: webview.WebviewController = new webview.WebviewController();
  /** 设置页滚动器（标题栏渐变模糊要 `bindToScrollable` 才跟着内容走）。 */
  private scroller: Scroller = new Scroller();
  /** 登录态（内存态；写 Cookie 后同步，供抽屉头/本页即时展示）。 */
  private session: SessionState = AppStorageV2.connect(SessionState, () => new SessionState())!;
  /** 系统安全区（顶部避让 = safeTop + 标题栏高 + 16 呼吸）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  /** 下载设置（页级并发；独立持久化 key）。 */
  private dlSettings: DownloadSettings = downloadSettings();
  /** 更新检查结果（持久化；版本号行的红点与副标题读它）。 */
  private updateStateRef: UpdateState = updateState();
  /** 手动检查进行中（防重复点击）。 */
  @Local updateChecking: boolean = false;

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  /** 显示模式即时生效（`setColorMode` 只运行时有效 → 同时落盘，冷启动由 `AppShell.onAppear` 重应用）。 */
  private applyDisplayMode(): void {
    try {
      this.context().getApplicationContext()
        .setColorMode(displayModeToColorMode(this.settings.displayMode));
    } catch (e) {
      Logger.error('Settings', `apply display mode failed: ${e}`);
    }
  }

  private async saveCookies(silent: boolean = false): Promise<void> {
    const store: CookieStore = new CookieStore();
    await store.init(this.context());
    if (this.ipbMemberId.length > 0) {
      store.set('ipb_member_id', this.ipbMemberId);
    }
    if (this.ipbPassHash.length > 0) {
      store.set('ipb_pass_hash', this.ipbPassHash);
    }
    if (this.igneous.length > 0) {
      store.set('igneous', this.igneous);
    }
    if (this.uconfig.length > 0) {
      store.set('uconfig', this.uconfig);
    }
    await store.flush();
    this.session.loggedIn = store.has('ipb_member_id');
    if (!silent) {
      this.message = '已保存 Cookie';
      promptAction.showToast({ message: this.message });
    }
  }

  /** 导出当前 Cookie：拼成 `k=v` 逐行，直接复制到系统剪贴板。 */
  private async exportCookies(): Promise<void> {
    try {
      const store: CookieStore = new CookieStore();
      await store.init(this.context());
      const jar: Record<string, string> = store.all();
      const keys: string[] = ['ipb_member_id', 'ipb_pass_hash', 'igneous', 'uconfig'];
      const lines: string[] = [];
      for (let i = 0; i < keys.length; i++) {
        const value: string | undefined = jar[keys[i]];
        if (value !== undefined && value.length > 0) {
          lines.push(`${keys[i]}=${value}`);
        }
      }
      if (lines.length === 0) {
        promptAction.showToast({ message: '当前没有可导出的 Cookie' });
        return;
      }
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n'));
      await pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: 'Cookie 已复制到剪贴板' });
    } catch (e) {
      Logger.error('Settings', `export cookies failed: ${e}`);
      promptAction.showToast({ message: '复制失败，请重试' });
    }
  }

  /** 导入：支持逐行 `k=v`，也兼容 `k=v; k2=v2` / `Cookie: k=v; ...`。 */
  private async importCookies(): Promise<void> {
    const jar: Record<string, string> = parseCookieString(this.cookieDraft);
    const keys: string[] = Object.keys(jar);
    if (keys.length === 0) {
      promptAction.showToast({ message: '先粘贴 Cookie' });
      return;
    }
    this.ipbMemberId = jar['ipb_member_id'] ?? '';
    this.ipbPassHash = jar['ipb_pass_hash'] ?? '';
    this.igneous = jar['igneous'] ?? '';
    this.uconfig = jar['uconfig'] ?? '';
    await this.saveCookies(true);
    this.message = `已导入 ${keys.length} 项 Cookie`;
    promptAction.showToast({ message: this.message });
    this.cookieDraft = '';
    this.sheetOpen = false;
  }

  /** 进页同步登录态（Cookie 本体已落盘，按需重算；登出入口未做，态只增不减）。 */
  private async refreshLoginState(): Promise<void> {
    try {
      const store: CookieStore = new CookieStore();
      await store.init(this.context());
      this.session.loggedIn = store.has('ipb_member_id');
    } catch (e) {
      // 读不到就保持原态，不挡设置页
    }
  }

  private applyCookieString(raw: string): void {
    const jar: Record<string, string> = parseCookieString(raw);
    const memberId: string | undefined = jar['ipb_member_id'];
    const passHash: string | undefined = jar['ipb_pass_hash'];
    const ign: string | undefined = jar['igneous'];
    const uc: string | undefined = jar['uconfig'];
    if (memberId !== undefined) {
      this.ipbMemberId = memberId;
    }
    if (passHash !== undefined) {
      this.ipbPassHash = passHash;
    }
    if (ign !== undefined) {
      this.igneous = ign;
    }
    if (uc !== undefined) {
      this.uconfig = uc;
    }
  }

  private async readWebCookies(): Promise<void> {
    try {
      // 身份 cookie 分属不同域：forums / e-hentai / exhentai，需逐一读取并合并。
      const urls: string[] = [
        LOGIN_URL,
        'https://e-hentai.org/',
        'https://exhentai.org/'
      ];
      for (let i = 0; i < urls.length; i++) {
        const raw: string = await webview.WebCookieManager.fetchCookie(urls[i]);
        this.applyCookieString(raw);
      }
      if (this.ipbMemberId.length > 0 && this.ipbPassHash.length > 0) {
        await this.saveCookies();
        await this.fetchIgneous();
        this.showWeb = false;
      }
    } catch (e) {
      this.message = `读取 Cookie 失败：${e}`;
    }
  }

  /** 登录后访问一次 EX 以取得 `igneous`（EX 会员态所需）。 */
  private async fetchIgneous(): Promise<void> {
    try {
      const store: CookieStore = new CookieStore();
      await store.init(this.context());
      const client: EhClient = new EhClient(new RcpHttpClient(), store);
      await client.getGalleryList(EhSite.EX, EhUrl.frontPage(EhSite.EX));
    } catch (e) {
      // igneous 获取失败不阻断登录
    }
  }

  /**
   * 打开站端页（源 `UConfigActivity`/`MyTagsActivity` 薄包：站内页直编服务端数据，
   * 进页种 Cookie、出页写回，无本地键解析）。未登录不进。
   */
  private async openSitePage(url: string, guard: string): Promise<void> {
    try {
      const store: CookieStore = new CookieStore();
      await store.init(this.context());
      if (!store.has('ipb_member_id')) {
        promptAction.showToast({ message: guard });
        return;
      }
      const jar: Record<string, string> = store.all();
      const keys: string[] = Object.keys(jar);
      for (let i = 0; i < keys.length; i++) {
        webview.WebCookieManager.configCookieSync(url, `${keys[i]}=${jar[keys[i]]}`);
      }
      this.sitePageUrl = url;
    } catch (e) {
      this.message = '打开页面失败，请重试';
    }
  }

  /** 打开半模态：诊断页要先算好副标题（`bindSheet` 打开后再改状态不会重绘）。 */
  private openSheet(kind: number): void {
    if (kind === 2) {
      this.refreshDiag();
    }
    this.sheetKind = kind;
    this.sheetOpen = true;
  }

  /** 重算诊断日志占用 + 最近崩溃时间。 */
  private refreshDiag(): void {
    this.diagText = statsSummary(DiagLog.stats(), Date.now());
  }

  /** 清空日志：确认 → 删文件 → 刷新副标题。 */
  private confirmClearLogs(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '清空日志',
      message: '删除本机保存的全部诊断日志？已经分享出去的文件不受影响。',
      buttons: [{ text: '取消', color: '#8C8C8C' }, { text: '清空', color: '#D94838' }]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index !== 1) {
        return;
      }
      DiagLog.clear();
      this.refreshDiag();
      promptAction.showToast({ message: '日志已清空' });
    }).catch((e: object) => {
      Logger.error('Settings', `clear logs dialog failed: ${e}`);
      promptAction.showToast({ message: '清空失败，请重试' });
    });
  }

  /** 打包并分享诊断日志（zip 里已脱敏；失败只 toast，细节进日志）。 */
  private async shareLogs(): Promise<void> {
    if (this.diagBusy) {
      return;
    }
    this.diagBusy = true;
    try {
      const meta: ExportMeta = {
        version: APP_VERSION_NAME,
        apiVersion: deviceInfo.sdkApiVersion,
        model: deviceInfo.productModel,
        site: this.settings.site === EhSite.E ? 'E-Hentai' : 'ExHentai',
        lang: i18n.System.getSystemLanguage(),
        loggedIn: this.session.loggedIn,
        exportedAtMs: Date.now()
      };
      const zipPath: string = await LogExport.pack(this.context(), meta);
      await LogExport.share(this.context(), zipPath);
    } catch (e) {
      Logger.error('Diag', `export failed: ${e}`);
      promptAction.showToast({ message: '打包失败，请重试' });
    } finally {
      this.diagBusy = false;
    }
  }

  /** 刷新缓存占用（与系统「设置-存储」同口径：`BundleStats.cacheSize`）。 */
  private async refreshCache(): Promise<void> {
    try {
      const bytes: number = await CacheManager.cacheSize();
      this.cacheText = formatBytes(bytes);
    } catch (e) {
      Logger.error('Settings', `cache stats failed: ${e}`);
      this.cacheText = '统计失败';
    }
  }

  /** 清缓存：确认 → 清模块级 + 应用级 cacheDir → 重新统计。 */
  private confirmClearCache(): void {
    if (this.cacheBusy) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '清理缓存',
      message: '清除图片与预览缓存？收藏、历史与设置不受影响。',
      buttons: [{ text: '取消', color: '#8C8C8C' }, { text: '清理', color: '#3D6BE5' }]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.clearCache();
      }
    }).catch((_e: object) => {
      // 对话框自身失败不影响设置页
    });
  }

  private async clearCache(): Promise<void> {
    this.cacheBusy = true;
    try {
      await CacheManager.clear(this.context());
      await this.refreshCache();
      promptAction.showToast({ message: '缓存已清理' });
    } catch (e) {
      Logger.error('Settings', `clear cache failed: ${e}`);
      promptAction.showToast({ message: '清理失败，请重试' });
    }
    this.cacheBusy = false;
  }

  /** 手动检查更新：结果用 toast 就地反馈（说明原文仍只在冷启动提示里）。 */
  private async checkUpdates(): Promise<void> {
    if (this.updateChecking) {
      return;
    }
    this.updateChecking = true;
    try {
      const ok: boolean = await UpdateManager.check();
      if (!ok) {
        promptAction.showToast({ message: '检查失败，请稍后重试' });
      } else if (hasUpdate(this.updateStateRef, APP_VERSION_NAME)) {
        promptAction.showToast({ message: `发现新版本 ${this.updateStateRef.latestVersion}` });
      } else {
        promptAction.showToast({ message: '已是最新版本' });
      }
    } catch (e) {
      Logger.error('Update', `manual check failed: ${e}`);
      promptAction.showToast({ message: '检查失败，请稍后重试' });
    } finally {
      this.updateChecking = false;
    }
  }

  /** 「下载」：系统保存面板 → 交给系统下载服务；取消不报错。 */
  private async downloadUpdate(): Promise<void> {
    const result: DownloadStart = await UpdateManager.pickAndStart(this.context());
    if (result === DownloadStart.STARTED) {
      promptAction.showToast({ message: '已开始下载，进度见通知栏；下载完请用自签工具签名后安装' });
    } else if (result === DownloadStart.NO_URL) {
      promptAction.showToast({ message: '没有可下载的地址' });
    } else if (result === DownloadStart.FAILED) {
      promptAction.showToast({ message: '下载没能开始，请重试' });
    }
  }

  /** 交给系统浏览器打开。 */
  private openUrl(url: string): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    ctx.startAbility(want).catch((e: object) => {
      Logger.error('Update', `open url failed: ${e}`);
      promptAction.showToast({ message: '打不开浏览器' });
    });
  }

  /** 官方入口：系统「设置-应用信息」页（存储/权限都在里面，由系统统一管理）。 */
  private openSystemAppInfo(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: { pushParams: ctx.applicationInfo.name }
    };
    ctx.startAbility(want).catch((e: object) => {
      Logger.error('Settings', `open app info failed: ${e}`);
      promptAction.showToast({ message: '打不开系统设置' });
    });
  }

  /** 打开 UConfig（站端 `uconfig.php` 直编服务端展示偏好，值走 `uconfig` cookie）。 */  private openUconfig(): void {
    this.openSitePage(EhUrl.uconfig(this.settings.site), '登录后修改高级设置');
  }

  /** 打开我的标签（站端 `mytags` 管理关注标签）。 */
  private openMyTags(): void {
    this.openSitePage(EhUrl.myTags(this.settings.site), '登录后查看我的标签');
  }

  /** 打开站点设置（My Home → My Settings：排除语言/上传者、过滤阈值）。 */
  private openMySettings(): void {
    this.openSitePage(`${EhUrl.host(this.settings.site)}home.php`, '登录后修改站点设置');
  }

  /**
   * 返回链：Web 站内能回退就先回退（与浏览器一致），退不动再关浮层回到设置页。
   * 浮层不是独立页面，所以必须自己接管返回；否则标题栏 ← / 系统手势会直接把设置页弹掉。
   * 返回 `true` 表示已消费，`false` 交回默认的页面 pop。
   */
  private handleBack(): boolean {
    if (!this.showWeb && this.sitePageUrl.length === 0) {
      return false;
    }
    if (this.controller.accessBackward()) {
      this.controller.backward();
      return true;
    }
    if (this.sitePageUrl.length > 0) {
      this.closeSitePage();
    } else {
      this.showWeb = false;
    }
    return true;
  }

  /** 关站端页：把 Web 侧可能更新的 Cookie（含 `uconfig`）写回 App。 */
  private async closeSitePage(): Promise<void> {
    try {
      const url: string = this.sitePageUrl;
      const raw: string = await webview.WebCookieManager.fetchCookie(url);
      this.applyCookieString(raw);
      await this.saveCookies();
    } catch (e) {
      this.message = `读取 Cookie 失败：${e}`;
    }
    this.sitePageUrl = '';
  }

  /** 预加载页数行：标题 + 当前值 + 0–10 滑块（`which` 0=前向 / 1=后向）。 */
  @Builder
  prefetchRow(label: string, which: number) {
    Column({ space: 4 }) {
      Row() {
        Text(label)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        // 直接读 `AppSettings`（@Builder 的参数是快照，用参数会让数字不跟手）。
        Text(`${which === 0 ? this.settings.prefetchAhead : this.settings.prefetchBehind} 页`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Slider({
        value: which === 0 ? this.settings.prefetchAhead : this.settings.prefetchBehind,
        min: PREFETCH_MIN,
        max: PREFETCH_MAX,
        step: 1
      })
        .width('100%')
        .onChange((v: number) => {
          const n: number = clampPrefetch(v);
          if (which === 0) {
            this.settings.prefetchAhead = n;
          } else {
            this.settings.prefetchBehind = n;
          }
        })
    }
    .width('100%')
  }

  /** Cookie 导入半模态：只在这里出现输入框（导出走剪贴板，页面不常驻文本框）。 */
  @Builder
  sheetContent() {
    Column({ space: 12 }) {
      if (this.sheetKind === 1) {
        TextArea({
          text: this.cookieDraft,
          placeholder: '示例（把示例换成你自己的值）：\n' +
            'ipb_member_id=0000000\n' +
            'ipb_pass_hash=0123456789abcdef0123456789abcdef\n' +
            'igneous=example0000000000'
        })
          .width('100%')
          .height(160)
          .fontSize(13)
          .onChange((value: string) => {
            this.cookieDraft = value;
          })
        Button('导入')
          .width('100%')
          .onClick(() => { this.importCookies(); })
        Text('从浏览器或别处复制后整段粘贴进来就行（换行、分号都可以），导入后立即生效。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else {
        Text('日志只保存在本机，包含站点地址、画廊号、错误信息；不含账号密码和 Cookie。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Text(this.diagText)
          .fontSize(13)
          .width('100%')
        Button(this.diagBusy ? '正在打包…' : '分享日志')
          .width('100%')
          .enabled(!this.diagBusy)
          .onClick(() => { this.shareLogs(); })
        Button('清空日志')
          .width('100%')
          .backgroundColor($r('app.color.chip_danger_bg'))
          .fontColor($r('app.color.danger'))
          .onClick(() => { this.confirmClearLogs(); })
      }
    }
    .width('100%')
    .padding(16)
  }

  build() {
    HdsNavDestination() {
      if (this.showWeb) {
        Column() {
          Web({ src: LOGIN_URL, controller: this.controller })
            .width('100%')
            .layoutWeight(1)
            .onPageEnd(() => { this.readWebCookies(); })
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.windowState.safeTop + TITLE_BAR_H })
      } else if (this.sitePageUrl.length > 0) {
        Column() {
          Web({ src: this.sitePageUrl, controller: this.controller })
            .width('100%')
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.windowState.safeTop + TITLE_BAR_H })
      } else {
        Scroll(this.scroller) {
          Column({ space: 6 }) {
            // 顶部避让放进滚动内容：内容能钻到标题栏下，渐变模糊才有东西可糊。
            Column().height(this.windowState.safeTop + TITLE_BAR_H + 16)
            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '站点' }) })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '站点' },
                secondaryText: { text: this.settings.site === EhSite.E ? 'e-hentai.org' : 'exhentai.org' }
              },
              suffixItem: new SuffixSelect({
                value: this.settings.site === EhSite.E ? 'E-Hentai' : 'ExHentai',
                optionValues: ['E-Hentai', 'ExHentai'],
                optionSymbol: [],
                onSelect: (index: number, _text: string) => {
                  this.settings.site = index === 0 ? EhSite.E : EhSite.EX;
                }
              })
            })
            Text('E-Hentai（e-hentai.org）：公开站，无需登录即可浏览。' +
              '注意：已登录账号访问 E 站首页显示的是会员页（无画廊列表），要浏览请选 ExHentai。' +
              'ExHentai（exhentai.org）：需要登录，未登录只能看到 sad panda；完整目录，浏览和阅读请选它。')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
              .margin({ bottom: CARD_GAP })

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '显示' }) })
            HdsListItemCard({
              prefixItem: new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.sun_max') } }),
              textItem: { primaryText: { text: '显示模式' } },
              suffixItem: new SuffixSelect({
                value: DISPLAY_MODE_LABELS[this.settings.displayMode],
                optionValues: DISPLAY_MODE_LABELS,
                optionSymbol: [],
                onSelect: (index: number, _text: string) => {
                  this.settings.displayMode = index;
                  this.applyDisplayMode();
                }
              })
            })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '缩略图尺寸' },
                secondaryText: { text: '切换后重新加载列表生效；不同尺寸分别缓存' }
              },
              suffixItem: new SuffixSelect({
                value: THUMB_SIZE_OPTIONS[this.settings.thumbSize].label,
                optionValues: THUMB_SIZE_LABELS,
                optionSymbol: [],
                onSelect: (index: number, _text: string) => {
                  this.settings.thumbSize = index;
                }
              })
            })

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '阅读' }) })
            // 预加载窗口：0–10 可调（前向/后向各一个滑块）；阅读器取 `AppSettings` 的实时值。
            Column() {
              Column({ space: 10 }) {
                this.prefetchRow('前向预加载', 0)
                this.prefetchRow('后向预加载', 1)
                Text('预加载越多翻页越顺，但请求更频繁、更容易被站点限流。')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.bg_secondary'))
              .borderRadius(CARD_RADIUS)
            }
            .width('100%')
            .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
            .margin({ bottom: CARD_GAP })

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '存储' }) })
            // 缓存统计/清理：官方 `storageStatistics` + 清 `cacheDir`（模块级 + 应用级）。
            HdsListItemCard({
              textItem: {
                primaryText: { text: '缓存占用' },
                secondaryText: { text: this.cacheText }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.openSystemAppInfo(); }
            })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '清理缓存' },
                secondaryText: { text: '图片与预览缓存；收藏、历史与设置不受影响' }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.confirmClearCache(); }
            })
            Text('缓存统计与系统「设置-存储」同口径；点「缓存占用」可打开系统应用信息页。')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
              .margin({ bottom: CARD_GAP })

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '下载' }) })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '同时下载页数' },
                secondaryText: { text: '越大越快，也更容易触发站点限流（1–4）' }
              },
              suffixItem: new SuffixSelect({
                value: `${this.dlSettings.concurrency}`,
                optionValues: ['1', '2', '3', '4'],
                optionSymbol: [],
                onSelect: (index: number, _text: string) => {
                  this.dlSettings.concurrency = clampConcurrency(index + 1);
                }
              })
            })
            Text('下载只保存在应用内（不会出现在系统相册）；阅读时优先用已下载的图片。')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
              .margin({ bottom: CARD_GAP })

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '登录' }) })
            HdsListItemCard({
              prefixItem: new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.person') } }),
              textItem: {
                primaryText: { text: this.session.loggedIn ? '已登录' : '未登录' },
                secondaryText: { text: this.session.loggedIn ? 'Cookie 有效' : '用 Web 登录或手动填 Cookie' }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.showWeb = true; }
            })
            Text('账号密码直登会被站点拦截，请用 Web 登录或手动 Cookie。')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
              .margin({ bottom: CARD_GAP })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '导出 Cookie' },
                secondaryText: { text: '复制到剪贴板' }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.exportCookies(); }
            })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '导入 Cookie' },
                secondaryText: { text: '从浏览器复制后整段粘贴' }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.openSheet(1); }
            })

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '高级设置' }) })
            HdsListItemCard({
              prefixItem: new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.sort') } }),
              textItem: {
                primaryText: { text: 'UConfig' },
                secondaryText: { text: '站端展示偏好（评论排序、标签排序、多页阅读器等）' }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.openUconfig(); }
            })
            HdsListItemCard({
              prefixItem: new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.bookmark') } }),
              textItem: {
                primaryText: { text: '我的标签' },
                secondaryText: { text: '站内管理关注标签 / 屏蔽标签（My Tags）' }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.openMyTags(); }
            })
            HdsListItemCard({
              prefixItem: new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.gearshape') } }),
              textItem: {
                primaryText: { text: '站点设置' },
                secondaryText: { text: '排除语言 / 上传者、过滤阈值（My Settings）' }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.openMySettings(); }
            })
            Text('以上两项需登录，站内修改后返回自动同步。')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
              .margin({ bottom: CARD_GAP })

            if (this.message.length > 0) {
              Text(this.message)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '关于' }) })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '版本号' },
                secondaryText: {
                  text: hasUpdate(this.updateStateRef, APP_VERSION_NAME)
                    ? `${APP_VERSION_NAME} · 有新版本 ${this.updateStateRef.latestVersion}`
                    : APP_VERSION_NAME
                }
              },
              suffixItem: hasUpdate(this.updateStateRef, APP_VERSION_NAME)
                ? new SuffixBadgeAndArrow({ badgeValue: -1 }, { color: $r('app.color.danger') })
                : undefined
            })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '软件更新' },
                secondaryText: { text: updateSummary(this.updateStateRef, APP_VERSION_NAME) }
              },
              suffixItem: hasUpdate(this.updateStateRef, APP_VERSION_NAME)
                ? new SuffixButton({
                    text: '下载',
                    onClick: () => { this.downloadUpdate(); }
                  })
                : new SuffixButton({
                    text: this.updateChecking ? '检查中…' : '检查更新',
                    enable: !this.updateChecking,
                    onClick: () => { this.checkUpdates(); }
                  })
            })
            HdsListItemCard({
              textItem: {
                primaryText: { text: 'GitHub 项目' },
                secondaryText: { text: 'github.com/vaple/Ehviewer_ohos' }
              },
              suffixItem: new SuffixArrow({ color: $r('app.color.text_secondary') }),
              onClick: () => {
                this.openUrl('https://github.com/vaple/Ehviewer_ohos');
              }
            })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '诊断日志' },
                secondaryText: { text: this.diagText }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.openSheet(2); }
            })
          }
          .width('100%')
          .padding({ bottom: 16 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.bg_primary'))
      }
    }
    .titleBar({ avoidLayoutSafeArea: true, style: navTitleBarStyle(), content: { title: { mainTitle: '设置' } } })
    .bindToScrollable([this.scroller])
    .onBackPressed(() => this.handleBack())
    .bindSheet($$this.sheetOpen, this.sheetContent(), {
      title: { title: this.sheetKind === 1 ? '导入 Cookie' : '诊断日志' },
      systemMaterial: SHEET_MATERIAL,
      onDisappear: () => {
        this.sheetOpen = false;
      }
    })
    .onAppear(() => {
      this.refreshLoginState();
      this.refreshCache();
      this.refreshDiag();
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
    })
  }
}
