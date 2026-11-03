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
import { HdsListItemCard, HdsNavDestination, PrefixIcon, SuffixArrow, SuffixBadge, SuffixButton, SuffixSelect, SuffixSwitch } from '@kit.UIDesignKit';
import { CARD_GAP, CARD_RADIUS, PAGE_PADDING } from './Materials';
import { TITLE_BAR_H } from './NavStyle';
import { BundleStorage, CacheManager } from '../service/CacheManager';
import { formatBytes } from '../common/Bytes';
import { DiagLog, statsSummary } from '../service/DiagLog';
import { ExportMeta, LogExport } from '../service/LogExport';
import { VERSION_NAME } from 'BuildProfile';
import { clampPrefetch, PREFETCH_MAX, PREFETCH_MIN } from '../reader/PrefetchPlan';
import { navTitleBarStyle } from './NavStyle';
import { UpdateState, hasUpdate, updateState, updateSummary } from '../state/UpdateState';
import { DownloadStart, UpdateManager } from '../service/UpdateManager';
import { sharedDetailCache } from '../network/DetailCache';
import { TagSettings } from '../state/TagSettings';
import { TagDb, TagDbStatus } from '../tagdb/TagDb';
import { TagUpdateOutcome, updateTagDb } from '../service/TagDbUpdater';
import { errorText } from '../common/ErrorText';

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

/** 条数按千分位分组（`44795` → `44,795`）。不用 `toLocaleString`：结果会随系统语言变，状态行不该漂。 */
function formatTagCount(count: number): string {
  const digits: string = `${count}`;
  let out: string = '';
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) {
      out += ',';
    }
    out += digits.charAt(i);
  }
  return out;
}

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
  /** 存储占用（格式化后的展示串；`—` = 尚未统计）。四行数字一起换，避免半新半旧。 */
  @Local storageTotal: string = '—';
  @Local storageApp: string = '—';
  @Local storageData: string = '—';
  @Local storageCache: string = '—';
  /** 上一次统计是否失败（失败时行副标题直接说失败，不保留旧数字）。 */
  @Local storageFailed: boolean = false;
  @Local cacheBusy: boolean = false;
  /** Cookie 导入草稿（半模态里的输入框；导出直接进剪贴板，不在页面常驻文本框）。 */
  @Local cookieDraft: string = '';
  /** 半模态：`sheetKind` 1 = 导入 Cookie / 2 = 诊断日志 / 3 = 存储详情（一个节点只能挂一个 `bindSheet`）。 */
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
  /**
   * 标签翻译开关。独立持久化类（key 见 `state/TagSettings.ets` 的注释）；
   * `AppShell` 已用同一 key 连接过，`globalConnect` 返回同一个实例，这里只是拿到引用。
   */
  @Local tagSettings: TagSettings = PersistenceV2.globalConnect({
    type: TagSettings,
    key: 'TagSettings2',
    defaultCreator: () => new TagSettings()
  })!;
  /** 标签翻译更新进行中（防重复点击 + 按钮文案）。 */
  @Local tagUpdating: boolean = false;
  /** 本次会话最近一次更新失败的人话（不持久化：重启后不该继续展示旧失败）。技术细节在日志里。 */
  @Local tagUpdateError: string = '';

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
    // 登录态变了：详情缓存里存的是上一个账号（或游客）看到的收藏/评分状态，必须清掉。
    sharedDetailCache.clear();
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

  /** 打开「存储」半模态：数字必须**在打开前**算好（builder 只构建一次，见 `ui/AGENTS.md #20`）。 */
  private async openStorageSheet(): Promise<void> {
    await this.refreshStorage();
    this.sheetKind = 3;
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

  /**
   * 刷新存储占用（与系统「设置-存储-应用」同口径：`BundleStats`）。
   * 总计 = 应用 + 数据；缓存是数据的子集，**不重复相加**（官方 FAQ `faqs-local-file-manager-73`）。
   */
  private async refreshStorage(): Promise<void> {
    try {
      const stats: BundleStorage = await CacheManager.stats();
      this.storageTotal = formatBytes(stats.totalSize);
      this.storageApp = formatBytes(stats.appSize);
      this.storageData = formatBytes(stats.dataSize);
      this.storageCache = formatBytes(stats.cacheSize);
      this.storageFailed = false;
    } catch (e) {
      Logger.error('Settings', `storage stats failed: ${e}`);
      // 四行一起回 `—`：不能让半模态拿旧数字冒充新结果。
      this.storageTotal = '—';
      this.storageApp = '—';
      this.storageData = '—';
      this.storageCache = '—';
      this.storageFailed = true;
    }
  }

  /** 行副标题：统计失败就说失败，不留上一份数字。 */
  private storageSubtitle(): string {
    if (this.storageFailed) {
      return '统计失败';
    }
    return `总计 ${this.storageTotal} · 缓存 ${this.storageCache}`;
  }

  /** 半模态标题（一个 `bindSheet` 承载三种内容）。 */
  private sheetTitle(): string {
    if (this.sheetKind === 1) {
      return '导入 Cookie';
    }
    if (this.sheetKind === 2) {
      return '诊断日志';
    }
    return '存储';
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
      await this.refreshStorage();
      // 半模态内容只在打开时构建一次（#20）：不关掉就还是旧数字，看起来像没生效。
      this.sheetOpen = false;
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

  /** 状态行文案：开关关闭时 `status()` 是 undefined，必须显示「已关闭」而不是上一份快照。 */
  private tagStatusText(): string {
    if (!this.tagSettings.enabled) {
      return '已关闭';
    }
    const status: TagDbStatus | undefined = TagDb.status();
    if (status === undefined) {
      // 加载真的失败了就别再说「加载中…」：用户至少要知道去看诊断日志（按钮仍可点，点一次即重试）。
      return TagDb.hasFailed() ? '加载失败，详见诊断日志' : '加载中…';
    }
    const label: string = status.source === 'bundled' ? '内置快照' : '已更新';
    // `builtAt` 是 ISO8601 UTC，日期部分直接截取（不做时区换算：它就是数据生成那天的 UTC 日期）。
    return `${label} · ${status.builtAt.substring(0, 10)} · ${formatTagCount(status.count)} 条`;
  }

  /** 手动更新标签翻译：下载 → 转换 → 校验 → 原子写盘 → 重新加载，全程在 `TagDbUpdater` 里。 */
  private async updateTagTranslations(): Promise<void> {
    if (this.tagUpdating) {
      return;
    }
    this.tagUpdating = true;
    this.tagUpdateError = '';
    try {
      const outcome: TagUpdateOutcome = await updateTagDb(this.context());
      promptAction.showToast({ message: outcome === 'UP_TO_DATE' ? '已是最新' : '标签翻译已更新' });
    } catch (e) {
      // `TagDbUpdater` 已把原始异常记进日志；这里的 `e` 是它换好的人话。
      Logger.error('TagDb', `manual update failed: ${e}`);
      this.tagUpdateError = errorText(e);
      promptAction.showToast({ message: this.tagUpdateError });
    } finally {
      this.tagUpdating = false;
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

  /**
   * 打开系统「存储」页（设置应用注册的 uri 白名单之一，真机实测可用）。
   * 本应用的存储详情页（总计/应用/数据/缓存 + 清空缓存）**没有对外 uri**：`application_info_entry`
   * 只到应用信息页、`storage_settings` 也只到按应用分组的列表，参数（bundleName 等）选不中具体应用。
   * 所以这里只能把用户送到列表，再由用户点本应用；应用内的「存储」半模态才是主入口。
   */
  private openSystemStorage(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'storage_settings'
    };
    ctx.startAbility(want).catch((e: object) => {
      Logger.error('Settings', `open system storage failed: ${e}`);
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
      } else if (this.sheetKind === 2) {
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
      } else {
        // 存储明细：数字在打开半模态之前由 `openStorageSheet` 算好（builder 只构建一次）。
        this.storageRow('总计', this.storageTotal)
        Divider().color($r('app.color.divider'))
        this.storageRow('应用', this.storageApp)
        Divider().color($r('app.color.divider'))
        this.storageRow('数据', this.storageData)
        Divider().color($r('app.color.divider'))
        this.storageRow('缓存', this.storageCache)
        Text('总计 = 应用 + 数据；缓存包含在数据里，不重复计入。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Button(this.cacheBusy ? '正在清理…' : '清理缓存')
          .width('100%')
          .enabled(!this.cacheBusy)
          .onClick(() => { this.confirmClearCache(); })
        Button('在系统设置中查看')
          .width('100%')
          .backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.sheetOpen = false;
            this.openSystemStorage();
          })
      }
    }
    .width('100%')
    .padding(16)
  }

  /** 存储明细的一行（label 左、数值右）。 */
  @Builder
  storageRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(28)
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
            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '账号' }) })
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

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '标签翻译' }) })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '显示中文标签' },
                secondaryText: { text: '标签、命名空间与搜索候选都用中文；关闭会释放快照内存' }
              },
              suffixItem: new SuffixSwitch({
                isCheck: this.tagSettings.enabled,
                onChange: (isOn: boolean) => {
                  // 逐属性赋值：`enabled` 的 setter 会推送变化（关 → 释放数据，开 → 重新载入）。
                  // 重绘信号由 `TagDb` 内部自增（`dropData` / `install`），页面不要再写第二个。
                  this.tagSettings.enabled = isOn;
                }
              })
            })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '数据状态' },
                secondaryText: { text: this.tagStatusText() }
              }
            })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '翻译数据' },
                secondaryText: { text: '从 EhTagTranslation 下载最新词条（约 4 MB）' }
              },
              suffixItem: new SuffixButton({
                text: this.tagUpdating ? '更新中…' : '更新翻译',
                // 开关关着时不写盘：写进去也不会加载（`reload` 会直接返回空数据），只会被当成失败。
                enable: this.tagSettings.enabled && !this.tagUpdating,
                onClick: () => { this.updateTagTranslations(); }
              })
            })
            if (this.tagUpdateError.length > 0) {
              Text(`上次更新失败：${this.tagUpdateError}`)
                .fontSize(12)
                .fontColor($r('app.color.danger'))
                .width('100%')
                .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
                .margin({ bottom: CARD_GAP })
            }

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

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '存储' }) })
            // 占用明细与清理都收进一个半模态：系统的应用存储详情页没有对外 uri（见 `openSystemStorage`）。
            HdsListItemCard({
              textItem: {
                primaryText: { text: '存储占用' },
                secondaryText: { text: this.storageSubtitle() }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.openStorageSheet(); }
            })
            Text('总计 = 应用 + 数据；缓存包含在数据里。清理缓存只影响图片与预览，收藏、历史与设置不受影响。')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
              .margin({ bottom: CARD_GAP })

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
            Text('以上三项需登录，站内修改后返回自动同步。')
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

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '诊断' }) })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '诊断日志' },
                secondaryText: { text: this.diagText }
              },
              suffixItem: new SuffixArrow(),
              onClick: () => { this.openSheet(2); }
            })

            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '关于' }) })
            HdsListItemCard({
              textItem: {
                primaryText: { text: '版本号' },
                // 「有新版本」只在下面「软件更新」行说一次；这行只做信息展示。
                secondaryText: { text: APP_VERSION_NAME }
              },
              // 小红点只表示「有新版本」，不带箭头（这行没有点击行为）。
              suffixItem: hasUpdate(this.updateStateRef, APP_VERSION_NAME)
                ? new SuffixBadge({ badgeValue: -1, badgeColor: $r('app.color.danger') })
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
                primaryText: { text: '标签翻译数据' },
                secondaryText: { text: 'EhTagTranslation · GFDL / CC BY-NC-SA 3.0' }
              },
              // 上游数据以 GFDL / CC BY-NC-SA 3.0 分发：仓库开源、hap 随包带快照，署名必须能在这里点开。
              suffixItem: new SuffixArrow({ color: $r('app.color.text_secondary') }),
              onClick: () => {
                this.openUrl('https://github.com/EhTagTranslation/Database');
              }
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
      title: { title: this.sheetTitle() },
      // 存储明细只有四行 + 两个按钮：按内容高度贴合；另外两张沿用默认两档（内容更高，能拉大）。
      detents: this.sheetKind === 3 ? [SheetSize.FIT_CONTENT] : [SheetSize.MEDIUM, SheetSize.LARGE],
      onDisappear: () => {
        this.sheetOpen = false;
      }
    })
    .onAppear(() => {
      this.refreshLoginState();
      this.refreshStorage();
      this.refreshDiag();
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
    })
  }
}
