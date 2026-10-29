import { common } from '@kit.AbilityKit';
import { AppStorageV2, CapsuleSegmentButtonV2, PersistenceV2, SegmentButtonV2Items, window } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { GalleryDetail } from '../model/GalleryDetail';
import { GalleryPageResult } from '../parser/GalleryPageParser';
import { DetailParam } from '../model/DetailParam';
import { ReadingDirection, resolveStartPage, toDisplayIndex, toPage } from '../reader/ReaderMode';
import { clampPrefetch, neighbors, range } from '../reader/PrefetchPlan';
import { applyPinch, nextDoubleTapScale, clampOffset, ZOOM_MIN, ZOOM_MAX } from '../reader/ZoomModel';
import { ImageStore } from '../service/ImageStore';
import { PhotoSaver } from '../service/PhotoSaver';
import { downloadManager } from '../service/DownloadManager';
import { DownloadItem } from '../model/DownloadRecord';
import { Logger } from '../common/Logger';
import { errorText } from '../common/ErrorText';
import { GalleryDetailParser } from '../parser/GalleryDetailParser';
import { AppSettings } from '../state/AppSettings';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { ReadingProgressStore } from '../state/ReadingProgressStore';
import { WindowState } from '../state/WindowState';
import { SHEET_MATERIAL, TOUCH_MIN } from './Materials';
import { TITLE_BAR_H } from './NavStyle';
import { setDiagContext } from '../service/CrashCollector';

/** 单页图片地址：落盘后就地刷新该项（`@Trace`），不再整表 `slice()` 重组。 */
@ObservedV2
class ReaderImage {
  @Trace url: string = '';
  /** 取页失败（空位显示「重新加载」；重新加载开始时清掉）。 */
  @Trace failed: boolean = false;
}

/** 纵向阅读项。`@ReusableV2`：状态只来自 `@Param`，复用时由框架自动重置。 */
@ReusableV2
@ComponentV2
struct ReaderImageItem {
  @Require @Param image: ReaderImage;
  @Require @Param index: number;
  @Event onLoaded: (index: number) => void = (_index: number) => {};
  @Event onRetry: (index: number) => void = (_index: number) => {};

  build() {
    Column() {
      if (this.image.url.length > 0) {
        Image(this.image.url)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .onComplete(() => { this.onLoaded(this.index); })
      } else if (this.image.failed) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(30)
            .fontColor([$r('app.color.brand')])
          Text('重新加载')
            .fontSize(13)
            .fontColor($r('app.color.brand'))
        }
        .padding(24)
        .onClick(() => {
          this.image.failed = false;
          this.onRetry(this.index);
        })
      } else {
        LoadingProgress().width(40).height(40).margin({ top: 60, bottom: 60 })
      }
    }
    .width('100%')
  }
}

/**
 * 阅读器：横向 `Swiper` 翻页，支持 LTR / RTL（反向映射），懒加载 + 顺序取 pToken，
 * 图片经 RCP（`Referer` + Cookie）落盘后由 `Image` 渲染；进度按 gid 记（**0 起**）。
 * 方向 / 图片地址 / 进度分别由 `AppSettings` / `@ObservedV2` 项 / `ReadingProgressStore` 承载。
 */
@ComponentV2
export struct ReaderPage {
  private static VERTICAL_MARGIN: number = 2;
  /** 取数代际（跳页/跳转即 +1；过期响应的 focus 写直接丢弃）。 */
  private generation: number = 0;
  private static PREVIEW_PER_CHUNK: number = 20;
  /** 点击手势移动阈值（vp）：超过即判为滑动，避免快滑被吞成单击（默认值是 2^31-1）。 */
  private static readonly TAP_SLOP: number = 10;
  /** 放大后单指平移手势的 tag：未放大时在 `onGestureJudgeBegin` 里拒绝它，把拖动让给 Swiper。 */
  private static readonly ZOOM_PAN_TAG: string = 'reader-zoom-pan';

  @Local settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  private progress: ReadingProgressStore = PersistenceV2.globalConnect({
    type: ReadingProgressStore,
    key: 'ReadingProgressStore',
    defaultCreator: () => new ReadingProgressStore()
  })!;
  @Local total: number = 0;
  @Local index: number = 0;
  @Local images: ReaderImage[] = [];
  /** 仅用于阻塞态/失败人话（页码不再走它，见 `pageLabel`）。 */
  @Local message: string = '';
  @Local ready: boolean = false;
  @Local imgScale: number = ZOOM_MIN;
  @Local imgOffsetX: number = 0;
  @Local imgOffsetY: number = 0;
  /** 当前页码（0 起）；被 `build()` 的进度条读取，所以是状态。 */
  @Local currentPage: number = 0;
  /** 进度条拖动中的目标页（`-1` = 未拖动；拖动时左下角实时显示这一页）。 */
  @Local scrubPage: number = -1;
  /** 转屏锁定（看完即走，不落盘；退出阅读恢复跟随系统）。 */
  @Local orientationLocked: boolean = false;
  /** 常亮开关（`init` 即开，退出关；sheet 内可手动开关）。 */
  @Local keepScreenOn: boolean = true;
  /** 阅读选项 sheet（半模态；底栏只留进度+页码+齿轮）。 */
  @Local showSettings: boolean = false;
  /** 沉浸：进页即藏系统栏（只做一次）；`chromeShown` 控制覆盖式操作栏。 */
  @Local immersive: boolean = false;
  /** 操作栏是否显示（单击切换；**不动系统栏、不动布局**，图片位置恒定）。 */
  @Local chromeShown: boolean = true;
  /** 阅读器窗口（进页时缓存；`setTimeout` 里不能 `getUIContext()`，切系统栏时复用它）。 */
  private readerWindow: window.Window | undefined = undefined;
  /** 状态栏高度：操作栏显示时顶栏要避让（否则时钟/电池压在标题和图标上）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  private pinchBase: number = ZOOM_MIN;
  private panBaseX: number = 0;
  private panBaseY: number = 0;
  private viewW: number = 0;
  private viewH: number = 0;
  private tokens: string[] = [];
  private skipHathKey: string = '';
  private gid: number = 0;
  private token: string = '';
  /** 预览点跳的指定起始页（`-1` = 无，走进度恢复）。 */
  private startPage: number = -1;
  /** 详情页带过来的总页数（等系统栏切完、图片槽建好后再写进 `total`，避免首帧空数组）。 */
  private pendingPages: number = 0;
  private client: EhClient | null = null;
  private store: ImageStore = new ImageStore();
  private site: EhSite = EhSite.E;
  private controller: SwiperController = new SwiperController();
  private listScroller: Scroller = new Scroller();
  private pageStack: NavPathStack | undefined = undefined;
  /** 纵向：列表是否正在滚动（滚动中不做重锚定，避免和用户手势打架）。 */
  private scrolling: boolean = false;
  /**
   * 纵向的**锚点页**：只有"恢复/用户明确选页/用户滚动停下"才更新它。
   * 不能用 `currentPage` 当锚：`onScrollIndex` 报的"顶部页"会被图片加载推小（漂移），拿它当锚等于锚跟着漂。
   */
  private anchorPage: number = 0;
  /** 纵向：把视口重新锚回 `anchorPage` 的剩余预算（图片加载完成时用）。 */
  private reanchorBudget: number = 40;

  /** 横向 `Swiper` 的显示索引序列（`total` 变才重算）。 */
  @Computed
  get pageIndices(): number[] {
    const list: number[] = [];
    for (let i = 0; i < this.total; i++) {
      list.push(i);
    }
    return list;
  }

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  /** 当前显示页（0 起）：横向按显示索引反解，纵向用滚动回报的顶部页。 */
  private displayPage(): number {
    if (this.total <= 0) {
      return 0;
    }
    if (this.settings.readerDirection === ReadingDirection.VERTICAL) {
      return this.currentPage;
    }
    return toPage(this.index, this.total, this.settings.readerDirection);
  }

  /** 沉浸切换的待触发定时器（单击延迟一拍，给双击让路；0 = 无待触发）。 */
  private immersiveTimer: number = 0;
  /** 上次双击的时间戳：第二次抬起同样会触发 `count:1`，靠它压住紧随其后的那一次单击。 */
  private lastDoubleTap: number = 0;

  /**
   * 单击切操作栏：延迟 280ms 再执行（标准双击消歧，和 Android 的 double-tap-timeout 同构）。
   * 若期间来了双击，`cancelImmersiveSoon` 会取消它 —— 单击不会误触，页面也不会闪一下。
   */
  private toggleImmersiveSoon(): void {
    if (this.scrolling || Date.now() - this.lastDoubleTap < 350) {
      return;
    }
    this.cancelImmersiveSoon();
    this.immersiveTimer = setTimeout(() => {
      this.immersiveTimer = 0;
      // 只切覆盖层：系统栏在进页时已经藏好，切换操作栏不再改窗口 → 图片不位移。
      // 注意：不要在 `setTimeout` 里 `getUIContext()`（脱离 UI 上下文会抛错，切换静默失效）；
      // 淡入淡出交给两个操作栏包装层上的 `.transition(...)`。
      this.chromeShown = !this.chromeShown;
      // 操作栏出现时把状态栏（时间/电量）一起带出来；收起时再藏回去。
      this.setStatusBarVisible(this.chromeShown);
    }, 280);
  }

  private cancelImmersiveSoon(): void {
    if (this.immersiveTimer !== 0) {
      clearTimeout(this.immersiveTimer);
      this.immersiveTimer = 0;
    }
  }
  /** 常亮：阅读时保持屏幕常亮。失败记日志 + 人话，不阻塞阅读。 */
  private async setKeepScreenOn(on: boolean): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      await win.setWindowKeepScreenOn(on);
    } catch (e) {
      Logger.error('Reader', `setKeepScreenOn(${on}) failed: ${e}`);
      this.message = '常亮设置失败，请重试';
    }
  }

  /**
   * 退出阅读恢复系统栏；应用级全屏布局保持开启（见 `EntryAbility`），只把状态栏/导航栏显示回来。
   */
  private async restoreWindow(): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      await win.setWindowSystemBarEnable(['status', 'navigation']);
      await win.setWindowLayoutFullScreen(true);
      this.immersive = false;
    } catch (e) {
      Logger.error('Reader', `restore window failed: ${e}`);
    }
  }

  /**
   * 沉浸开关：全屏布局 + 藏/显状态栏与导航栏；`immersive` 只在成功后翻转。
   * 失败记日志 + 人话，UI 保持原状（不出现"开关已切、系统栏还在"的表里不一）。
   */
  private async setImmersive(on: boolean): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      this.readerWindow = win;
      await win.setWindowLayoutFullScreen(on);
      await win.setWindowSystemBarEnable(on ? [] : ['status', 'navigation']);
      this.immersive = on;
    } catch (e) {
      Logger.error('Reader', `setImmersive(${on}) failed: ${e}`);
      this.message = '全屏设置失败，请重试';
    }
  }

  /**
   * 操作栏显隐时联动状态栏（需要看时间/电量）。
   * 用进页缓存的窗口对象：这个函数会在 `setTimeout` 里被调用，不能在那里取 `getUIContext()`。
   */
  private setStatusBarVisible(visible: boolean): void {
    const win: window.Window | undefined = this.readerWindow;
    if (win === undefined) {
      return;
    }
    win.setWindowLayoutFullScreen(true)
      .then(() => win.setWindowSystemBarEnable(visible ? ['status'] : []))
      .catch((e: object) => {
        Logger.error('Reader', `status bar visible=${visible} failed: ${e}`);
      });
  }

  private async ensureClient(): Promise<EhClient> {
    if (this.client !== null) {
      return this.client;
    }
    this.site = this.settings.site;
    const cookies: CookieStore = new CookieStore();
    await cookies.init(this.context());
    this.client = new EhClient(new RcpHttpClient(), cookies);
    return this.client;
  }

  private async init(): Promise<void> {
    // 进页即全屏（只做一次）：之后单击只切覆盖层，窗口/布局不再变化 → 图片不位移。
    // 先等窗口切完再建首帧，避免「先按有系统栏布局、再按无系统栏重排」的一次性跳动。
    await this.setImmersive(true);
    // 进页时操作栏是显示的 → 状态栏也一起显示；单击收起时再藏。
    this.setStatusBarVisible(true);
    await downloadManager.init(this.context());
    await downloadManager.prepareLocal(this.gid);
    setDiagContext(`page=reader gid=${this.gid}`);
    const local: DownloadItem | undefined = downloadManager.itemOf(this.gid);
    const hasLocal: boolean = local !== undefined && local.pages > 0;
    // 总页数在**建好图片槽之后**才生效：否则 total>0 而 images 还空，首帧访问 images[page] 会崩。
    if (this.pendingPages > 0) {
      this.total = this.pendingPages;
    } else if (hasLocal && local !== undefined) {
      // 离线打开（从「下载」进来）：先用本地清单撑起页数，不等网络。
      this.total = local.pages;
    }
    this.ensureImages();
    this.prepareStart();
    this.prefillLocal();
    try {
      const client: EhClient = await this.ensureClient();
      await this.store.init(this.context());

      const detail: GalleryDetail | null =
        await client.getGalleryDetail(this.site, this.gid, this.token);
      if (detail === null) {
        Logger.error('Reader', `getGalleryDetail returned null gid=${this.gid}`);
        this.ready = true;
        if (hasLocal) {
          this.message = '离线模式';
          await this.loadPage(this.currentPage);
        } else {
          this.message = errorText(null, GalleryDetailParser.lastReason());
        }
        return;
      }
      if (detail.pages > 0) {
        this.total = detail.pages;
      }
      this.tokens = detail.previewTokens.slice();
      if (this.total <= 0) {
        Logger.error('Reader', `no pages gid=${this.gid}`);
        this.message = '没有可阅读的页面';
        this.ready = true;
        return;
      }
      this.ensureImages();
      this.prepareStart();
      this.prefillLocal();
      this.ready = true;
      await this.setKeepScreenOn(true);
      await this.loadPage(this.currentPage);
    } catch (e) {
      Logger.error('Reader', `init failed gid=${this.gid}: ${e}`);
      this.ready = true;
      if (hasLocal) {
        this.message = '离线模式';
        await this.loadPage(this.currentPage);
      } else {
        this.message = errorText(e as Object);
      }
    }
  }

  /** 按总页数建图片槽（幂等；总页数变化才重建）。详情页给了 `pages` 时首帧就能渲染。 */
  private ensureImages(): void {
    if (this.total <= 0 || this.images.length === this.total) {
      return;
    }
    const images: ReaderImage[] = [];
    for (let i = 0; i < this.total; i++) {
      images.push(new ReaderImage());
    }
    this.images = images;
  }

  /** 起始页 = 预览点跳 > 阅读进度恢复；同时把显示索引/锚点对齐（幂等）。 */
  private prepareStart(): void {
    if (this.total <= 0) {
      return;
    }
    let page: number = resolveStartPage(this.progress.load(this.gid), this.total);
    if (this.startPage >= 0 && this.startPage < this.total) {
      page = this.startPage;
    }
    this.currentPage = page;
    this.anchorPage = page;
    this.reanchorBudget = 40;
    this.index = toDisplayIndex(page, this.total, this.settings.readerDirection);
  }

  /** 已下载页的本地 URI 一次性同步填槽：翻页不出现空槽（下载完的整本画廊零等待）。 */
  private prefillLocal(): void {
    for (let i = 0; i < this.total && i < this.images.length; i++) {
      if (this.images[i].url.length > 0) {
        continue;
      }
      const uri: string = downloadManager.localUriIfLoaded(this.gid, i);
      if (uri.length > 0) {
        this.images[i].url = uri;
      }
    }
  }

  /** 取某页 pToken；详情页未给出的（>20 页）按预览分块补取。失败直接抛给 `loadPage` 边界处理。 */
  private async ensureToken(page: number): Promise<string | undefined> {
    let pToken: string | undefined = this.tokens[page];
    if (pToken !== undefined) {
      return pToken;
    }
    const client: EhClient = await this.ensureClient();
    const chunk: number = Math.floor(page / ReaderPage.PREVIEW_PER_CHUNK);
    const fetched: string[] =
      await client.getPreviewTokens(this.site, this.gid, this.token, chunk);
    for (let i = 0; i < fetched.length; i++) {
      if (fetched[i] !== undefined && this.tokens[i] === undefined) {
        this.tokens[i] = fetched[i];
      }
    }
    return this.tokens[page];
  }

  private async loadPage(page: number, focus: boolean = true): Promise<void> {
    if (page < 0 || page >= this.total) {
      return;
    }
    this.images[page].failed = false;
    // 代际快照：连跳时过期响应的 focus 写（页码/消息/进度）直接丢弃，不回写旧页。
    const gen: number = this.generation;
    if (focus && gen === this.generation) {
      this.currentPage = page;
    }
    // 已下载页优先读本地：翻页时**同步**命中映射（不 await），避免每页一次异步空档。
    const localSync: string = downloadManager.localUriIfLoaded(this.gid, page);
    if (localSync.length > 0) {
      this.images[page].url = localSync;
      if (focus && gen === this.generation) {
        this.message = '';
        this.progress.save(this.gid, page);
        // 已下载画廊也要预取邻居：否则只有当前页有槽，翻页会闪一下加载圈（在线路径有预取，反而更顺）。
        this.prefetch(page);
      }
      return;
    }
    // 映射尚未加载时的兜底（例如直接进阅读器且 init 还没跑完）。
    const local: string = await downloadManager.localUri(this.gid, page);
    if (local.length > 0) {
      this.images[page].url = local;
      if (focus && gen === this.generation) {
        this.message = '';
        this.progress.save(this.gid, page);
        this.prefetch(page);
      }
      return;
    }
    let pToken: string | undefined;
    try {
      pToken = await this.ensureToken(page);
    } catch (e) {
      Logger.error('Reader', `page ${page + 1}: preview chunk fetch failed: ${e}`);
      this.images[page].failed = true;
      if (focus && gen === this.generation) {
        this.message = `第 ${page + 1} 页加载失败，请重试`;
      }
      return;
    }
    if (pToken === undefined) {
      Logger.error('Reader', `page ${page + 1}: preview token still missing after chunk fetch`);
      this.images[page].failed = true;
      if (focus && gen === this.generation) {
        this.message = `第 ${page + 1} 页加载失败，请重试`;
      }
      return;
    }
    try {
      const client: EhClient = await this.ensureClient();
      const nl: string | undefined = this.skipHathKey.length > 0 ? this.skipHathKey : undefined;
      const result: GalleryPageResult =
        await client.getGalleryPage(this.site, this.gid, page + 1, pToken, nl);
      if (result.skipHathKey !== null) {
        this.skipHathKey = result.skipHathKey;
      }
      if (result.nextPToken !== null) {
        this.tokens[page + 1] = result.nextPToken;
      }

      const url: string = result.imageUrl;
      const pageUrl: string = EhUrl.galleryPage(this.site, this.gid, page + 1, pToken, nl);
      let local: string;
      try {
        local = await this.store.get(client, url, pageUrl);
      } catch (e) {
        Logger.error('Reader', `page ${page + 1}: image download failed: ${e}`);
        this.images[page].failed = true;
        if (focus && gen === this.generation) {
          this.message = `第 ${page + 1} 页加载失败，请重试`;
        }
        return;
      }
      this.images[page].url = local;

      if (focus && gen === this.generation) {
        this.message = '';
        this.progress.save(this.gid, page);
        this.prefetch(page);
      }
    } catch (e) {
      Logger.error('Reader', `page ${page + 1}: gallery page request failed: ${e}`);
      this.images[page].failed = true;
      if (focus && gen === this.generation) {
        this.message = `第 ${page + 1} 页加载失败，请重试`;
      }
    }
  }

  /** 预取相邻页（`focus=false`，静默：不改 `message`/`currentPage`，失败忽略；并发打，当前页优先由调用方保证）。 */
  private async prefetch(page: number): Promise<void> {
    // 前后页数来自设置（0–10，默认前 3 后 10）；`clampPrefetch` 兜住旧数据/非法值。
    const targets: number[] = neighbors(page, this.total,
      clampPrefetch(this.settings.prefetchAhead), clampPrefetch(this.settings.prefetchBehind));
    const tasks: Promise<void>[] = [];
    for (let i = 0; i < targets.length; i++) {
      if (this.images[targets[i]].url.length === 0) {
        tasks.push(this.loadPage(targets[i], false));
      }
    }
    await Promise.all(tasks);
  }

  /** 复位缩放/平移（切页时调用，避免下一页继承错位）。 */
  private resetZoom(): void {
    this.imgScale = ZOOM_MIN;
    this.imgOffsetX = 0;
    this.imgOffsetY = 0;
    this.pinchBase = ZOOM_MIN;
    this.panBaseX = 0;
    this.panBaseY = 0;
  }

  /** 可缩放图片：捏合缩放、双击放大/复位、放大后单指拖动平移。 */
  @Builder
  zoomableImage(src: string) {
    Image(src)
      .objectFit(ImageFit.Contain)
      .width('100%')
      .height('100%')
      .scale({ x: this.imgScale, y: this.imgScale })
      .translate({ x: this.imgOffsetX, y: this.imgOffsetY })
      // 并行竞技场 + 延迟消歧：单击走 `toggleImmersiveSoon`（280ms 后才切），
      // 双击先到就取消待触发再缩放 —— 捏合/拖动与原来一样共存。
      // 关键：`distanceThreshold` 必须给（默认 2^31-1 = 手指不离开就算点击，滑动会被吞成单击）。
      .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult => {
        // 未放大时把单指拖动让给外层 Swiper（否则 Pan 抢到拖动、页面不翻）。
        if (info.tag === ReaderPage.ZOOM_PAN_TAG && this.imgScale <= ZOOM_MIN) {
          return GestureJudgeResult.REJECT;
        }
        return GestureJudgeResult.CONTINUE;
      })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          // 单击/双击都限制移动阈值：超过就是滑动，分别让给 Swiper / 平移。
          TapGesture({ count: 1, distanceThreshold: ReaderPage.TAP_SLOP })
            .onAction(() => {
              this.toggleImmersiveSoon();
            }),
          PinchGesture({ fingers: 2 })
            .onActionStart(() => { this.pinchBase = this.imgScale; })
            .onActionUpdate((e: GestureEvent) => {
              this.imgScale = applyPinch(this.pinchBase, e.scale, ZOOM_MIN, ZOOM_MAX);
              this.imgOffsetX = clampOffset(this.imgOffsetX, this.viewW, this.imgScale);
              this.imgOffsetY = clampOffset(this.imgOffsetY, this.viewH, this.imgScale);
            }),
          TapGesture({ count: 2, distanceThreshold: ReaderPage.TAP_SLOP })
            .onAction(() => {
              this.cancelImmersiveSoon();
              this.lastDoubleTap = Date.now();
              this.imgScale = nextDoubleTapScale(this.imgScale, ZOOM_MAX);
              if (this.imgScale <= ZOOM_MIN) {
                this.imgOffsetX = 0;
                this.imgOffsetY = 0;
              }
            }),
          PanGesture({ fingers: 1, distance: 10 })
            .tag(ReaderPage.ZOOM_PAN_TAG)
            .onActionStart(() => {
              this.cancelImmersiveSoon();
              this.panBaseX = this.imgOffsetX;
              this.panBaseY = this.imgOffsetY;
            })
            .onActionUpdate((e: GestureEvent) => {
              if (this.imgScale <= ZOOM_MIN) {
                return;
              }
              this.imgOffsetX = clampOffset(this.panBaseX + e.offsetX, this.viewW, this.imgScale);
              this.imgOffsetY = clampOffset(this.panBaseY + e.offsetY, this.viewH, this.imgScale);
            })
        )
      )
  }

  /** `Swiper.index` 用 `$$` 双向绑定（它不在 `!!` 支持表内），所以这里不再手写 `this.index = i`。 */
  private onIndexChange(i: number): void {
    if (this.total <= 0) {
      return;
    }
    // 滑动（`onIndexChange` 只由 `Swiper.onChange` 触发）时取消待触发的单击切换：点按后 280ms 内滑动不再附带切沉浸。
    this.cancelImmersiveSoon();
    this.resetZoom();
    this.generation += 1;
    const page: number = toPage(i, this.total, this.settings.readerDirection);
    this.loadPage(page);
  }

  /** 进度条跳页：直接切到显示索引 `displayIndex` 并加载该页（缺 pToken 会按分块补取）。 */
  private jumpTo(displayIndex: number): void {
    if (this.total <= 0) {
      return;
    }
    const v: number = Math.max(0, Math.min(this.total - 1, displayIndex));
    this.index = v;
    this.controller.changeIndex(v);
    this.generation += 1;
    this.loadPage(toPage(v, this.total, this.settings.readerDirection));
  }

  /** 存图的目标页：横向按显示索引映射；纵向用锚点页（`currentPage` 会被漂移改写，不能用）。 */
  private savePage(): number {
    if (this.settings.readerDirection === ReadingDirection.VERTICAL) {
      return this.anchorPage;
    }
    return toPage(this.index, this.total, this.settings.readerDirection);
  }

  /** 存当前页到相册：无缓存先加载仍无则报错；失败记日志 + 人话，不做降级。 */
  private async saveCurrentPage(): Promise<void> {
    const page: number = this.savePage();
    try {
      let url: string = this.images[page].url;
      if (url.length === 0) {
        await this.loadPage(page, false);
        url = this.images[page].url;
      }
      if (url.length === 0) {
        Logger.error('Reader', `save page ${page + 1}: image still not cached after load`);
        this.message = '图片尚未加载，请重试';
        return;
      }
      await PhotoSaver.saveToGallery(this.context(), url);
      this.message = '已保存到相册';
    } catch (e) {
      Logger.error('Reader', `save page ${page + 1} failed: ${e}`);
      this.message = '保存失败，请重试';
    }
  }

  /** 缓存 URI 的扩展名 → 精确图片 UTD；未知回 `IMAGE` 通用类型。 */
  private static imageUtd(uri: string): string {
    const dot: number = uri.lastIndexOf('.');
    const ext: string = dot >= 0 ? uri.substring(dot + 1).toLowerCase() : '';
    if (ext === 'jpg' || ext === 'jpeg') {
      return uniformTypeDescriptor.UniformDataType.JPEG;
    }
    if (ext === 'png') {
      return uniformTypeDescriptor.UniformDataType.PNG;
    }
    if (ext === 'gif') {
      return uniformTypeDescriptor.UniformDataType.GIF;
    }
    // 注：`UniformDataType` 无 WEBP 成员，webp 走通用 IMAGE。
    return uniformTypeDescriptor.UniformDataType.IMAGE;
  }

  /**
   * 分享当前页图片（只发图片；画廊链接走 `shareGalleryLink`）。
   * 没有可用分享目标时，面板本身仍应正常拉起。
   */
  private async shareCurrentPage(): Promise<void> {
    const page: number = this.savePage();
    try {
      let url: string = this.images[page].url;
      if (url.length === 0) {
        await this.loadPage(page, false);
        url = this.images[page].url;
      }
      if (url.length === 0) {
        Logger.error('Reader', `share page ${page + 1}: image still not cached after load`);
        this.message = '图片尚未加载，请重试';
        return;
      }
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: ReaderPage.imageUtd(url),
        uri: url,
        title: `第 ${page + 1} 页`
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const abilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await controller.show(abilityContext, { previewMode: systemShare.SharePreviewMode.DEFAULT });
    } catch (e) {
      Logger.error('Reader', `share page ${page + 1} failed: ${e}`);
      this.message = '分享失败，请重试';
    }
  }

  /** 分享画廊链接（纯链接，不带图片）。 */
  private async shareGalleryLink(): Promise<void> {
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
        content: EhUrl.galleryDetail(this.site, this.gid, this.token),
        title: '画廊链接'
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const abilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await controller.show(abilityContext, { previewMode: systemShare.SharePreviewMode.DEFAULT });
    } catch (e) {
      Logger.error('Reader', `share gallery link failed: ${e}`);
      this.message = '分享失败，请重试';
    }
  }

  /** 转屏锁定：锁定当前方向 ↔ 跟随系统（`AUTO_ROTATION_UNSPECIFIED` 受系统旋转锁控制）；退出阅读恢复跟随。 */
  private async toggleOrientationLock(): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      const next: boolean = !this.orientationLocked;
      await win.setPreferredOrientation(next
        ? window.Orientation.LOCKED
        : window.Orientation.AUTO_ROTATION_UNSPECIFIED);
      this.orientationLocked = next;
    } catch (e) {
      Logger.error('Reader', `orientation lock failed: ${e}`);
      this.message = '方向锁定失败，请重试';
    }
  }

  /** `SaveButton` 点击：只有授权成功才存；拒绝/失败记日志 + 人话。 */
  private onSaveClicked(result: SaveButtonOnClickResult): void {
    if (result !== SaveButtonOnClickResult.SUCCESS) {
      Logger.error('Reader', `save auth result=${result}`);
      this.message = result === SaveButtonOnClickResult.CANCELED_BY_USER ? '已取消保存' : '保存未获授权，请重试';
      return;
    }
    this.saveCurrentPage();
  }

  /** 方向直设（LTR/RTL/横向索引同步；纵向重建列表并放锚）。 */
  private setDirection(next: ReadingDirection): void {
    this.settings.readerDirection = next;
    if (next !== ReadingDirection.VERTICAL) {
      this.index = toDisplayIndex(this.currentPage, this.total, next);
      this.controller.changeIndex(this.index);
    } else {
      // 切到纵向会新建列表：把锚点放在用户当前页，并重置重锚定预算
      this.anchorPage = this.currentPage;
      this.reanchorBudget = 40;
      this.scrolling = false;
    }
  }

  /** 横向单页：已落盘 → 可缩放图；失败 → 重试；否则加载圈。 */
  @Builder
  horizontalPage(page: number) {
    if (this.images[page].url.length > 0) {
      this.zoomableImage(this.images[page].url)
    } else if (this.images[page].failed) {
      Column({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(30)
          .fontColor([$r('app.color.brand')])
        Text('重新加载')
          .fontSize(13)
          .fontColor($r('app.color.brand'))
      }
      .padding(24)
      .onClick(() => {
        this.images[page].failed = false;
        this.loadPage(page, true);
      })
    } else {
      LoadingProgress().width(40).height(40)
    }
  }

  /** 横向翻页（LTR / RTL）。 */
  @Builder
  horizontalPager() {
    Swiper(this.controller) {
      Repeat(this.pageIndices)
        .each((ri: RepeatItem<number>) => {
          Column() {
            this.horizontalPage(toPage(ri.item, this.total, this.settings.readerDirection))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        })
        .key((i: number) => `${i}`)
    }
    .index($$this.index)
    .loop(false)
    .indicator(false)
    // 放大后横向拖动是平移，不再翻页；缩回 1 倍后恢复。
    .disableSwipe(this.imgScale > ZOOM_MIN)
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    .onAreaChange((_o: Area, n: Area) => {
      this.viewW = Number(n.width);
      this.viewH = Number(n.height);
    })
    .onAnimationStart((_index: number, _target: number) => {
      // 翻页动画一起手就取消待触发的单击（快滑不切操作栏）。
      this.cancelImmersiveSoon();
    })
    .onChange((i: number) => { this.onIndexChange(i); })
  }

  /** 纵向阅读：不做 RTL 反转，滚动到哪加载到哪。 */
  @Builder
  verticalList() {
    // `initialIndex` 必须给：`onScrollIndex` 在列表初始化时会触发一次，若从 0 开始会
    // 把该 gid 的进度覆盖成 0（同时让"切到纵向"能停在当前页）。
    List({ scroller: this.listScroller, initialIndex: this.currentPage }) {
      // 不用 `virtualScroll`：懒加载用估算高度，`scrollToIndex`（进度条跳页）会落偏
      // （目标 45 页会停到 30 页附近）。全部建项才能保证高度精确；`@ReusableV2` 在增删项时仍生效。
      Repeat(this.images)
        .each((ri: RepeatItem<ReaderImage>) => {
          ListItem() {
            ReaderImageItem({
              image: ri.item,
              index: ri.index,
              onLoaded: (i: number) => { this.onImageLoaded(i); },
              onRetry: (i: number) => {
                this.loadPage(i, i === this.currentPage);
              }
            })
          }
        })
        .key((_item: ReaderImage, index: number) => `${index}`)
    }
    .width('100%')
    .layoutWeight(1)
    // 纵向项内无手势，点列表即走延迟切换（与横向一致的 280ms 消歧；纵向双击无缩放语义，
    // 第二次点击会取消第一次的待触发再重排，仍只切换一次）。
    .onClick(() => {
      this.toggleImmersiveSoon();
    }, ReaderPage.TAP_SLOP)
    .onScrollStart(() => {
      this.scrolling = true;
      // 一开始滚就取消待触发的单击（否则快速一划会被当成单击切操作栏）。
      this.cancelImmersiveSoon();
    })
    .onScrollStop(() => {
      this.scrolling = false;
      // 用户停下来的位置就是新的锚点；进度也只在这里（+ 恢复 / 进度条）写，避免被"漂移后的顶部页"改写。
      this.anchorPage = this.currentPage;
      this.reanchorBudget = 40;
      this.progress.save(this.gid, this.anchorPage);
    })
    .onScrollIndex((start: number, end: number) => {
      this.currentPage = start;
      const pages: number[] = range(start, end, this.total, ReaderPage.VERTICAL_MARGIN);
      for (let k = 0; k < pages.length; k++) {
        if (this.images[pages[k]].url.length === 0) {
          this.loadPage(pages[k], false);
        }
      }
    })
  }

  /**
   * 上方某页的图片加载完成 → 把视口重新锚回 `anchorPage`。
   * 为什么需要：`List` 是按**像素偏移**记滚动位置的，而一页的高度要等图片下载完才知道；
   * 上方那些项变高之后，同样的偏移就落到更靠前的页上（例如 62 → 58 → 57），
   * 于是 `onScrollIndex` 报的"顶部页"会一路变小。上游 Android 版 EhViewer（`ScrollLayoutManager`）用
   * `mKeepTopPageIndex`/`mKeepTop` 把"某一页 + 它的顶部偏移"当作锚来布局，所以它不漂；
   * ArkUI `List` 没有这个 API，这里用"重新 `scrollToIndex(anchorPage)`"等价地把它拉回来。
   */
  private onImageLoaded(index: number): void {
    if (this.scrolling || this.reanchorBudget <= 0 || index >= this.anchorPage) {
      return;
    }
    this.reanchorBudget -= 1;
    this.listScroller.scrollToIndex(this.anchorPage);
  }

  /** 顶栏右上分享菜单：链接 / 本页图片分开（保存仍在阅读选项 sheet）。 */
  @Builder
  shareMenu() {
    Menu() {
      MenuItem({ content: '分享画廊链接' })
        .onClick(() => {
          this.shareGalleryLink();
        })
      MenuItem({ content: '分享本页图片' })
        .onClick(() => {
          this.shareCurrentPage();
        })
    }
  }

  /** 顶部（覆盖式）：返回 + 标题 + 保存 + 分享。圆形按钮与详情页 HDS 标题栏同尺寸/同底。 */
  @Builder
  topBar() {
    Row({ space: 8 }) {
      // 官方 Button（Circle）负责居中图标：直接给 SymbolGlyph 设宽高只会撑占位盒、图标留在左上角。
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.reader_btn_bg'))
      .border({ width: 1, color: $r('app.color.reader_btn_ring') })
      .accessibilityText('返回')
      .onClick(() => {
        this.pageStack?.pop();
      })
      Text('阅读')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      // 官方安全控件（图标态）：点击即获媒体库临时授权；圆形与返回/分享同尺寸同底色。
      SaveButton({ icon: SaveIconStyle.LINES, buttonType: ButtonType.Circle })
        .userCancelEvent(true)
        .iconSize(20)
        .fontColor($r('app.color.text_primary'))
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.reader_btn_bg'))
        .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
          this.onSaveClicked(result);
        })
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.reader_btn_bg'))
      .border({ width: 1, color: $r('app.color.reader_btn_ring') })
      .accessibilityText('分享')
      .bindMenu(this.shareMenu)
    }
    .width('100%')
    .height(TITLE_BAR_H + this.windowState.safeTop)
    .padding({ left: 12, right: 12, top: this.windowState.safeTop })
    .alignItems(VerticalAlign.Center)
    // 官方 linearGradient 渐变遮罩：顶部不透明 → 靠图一侧透明（取代整条不透明 blur 的硬边）。
    .linearGradient({
      angle: 180,
      colors: [
        [$r('app.color.reader_chrome'), 0],
        [$r('app.color.reader_chrome_clear'), 1]
      ]
    })
  }

  /** 底部：进度条 + 页码 + 设置齿轮（选项全进 sheet）。 */
  @Builder
  bottomBar() {
    Column({ space: 4 }) {
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      // 进度条**故意保持单向**（不用 `$$`/`!!`）：连续双向写会让 `Swiper` 在拖动过程中
      // 逐页动画+加载；这里只在 `End`/`Click` 时提交一次（官方对"松开才生效"的常规做法）。
      Slider({
        value: this.settings.readerDirection === ReadingDirection.VERTICAL ? this.currentPage : this.index,
        min: 0,
        max: this.total - 1,
        step: 1
      })
        .width('100%')
        .onChange((value: number, mode: SliderChangeMode) => {
          const v: number = Math.round(value);
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            // 拖动中只更新左下角数字（不加载、不跳页）：松开才提交。
            this.scrubPage = v;
            return;
          }
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.scrubPage = -1;
            if (this.settings.readerDirection === ReadingDirection.VERTICAL) {
              // 进度条是"用户明确选页"的动作：程序化 `scrollToIndex` 不触发 `onScrollStart`，
              // 所以这里显式改锚 + 保存，不能只依赖滚动回调。
              this.anchorPage = v;
              this.reanchorBudget = 40;
              this.progress.save(this.gid, v);
              this.listScroller.scrollToIndex(v);
            } else {
              this.jumpTo(v);
            }
          }
        })
      Row({ space: 8 }) {
        // 页码是确定性的：分母来自详情（`DetailParam.pages`），拖动时显示目标页。
        Text(this.scrubPage >= 0
          ? `${this.scrubPage + 1} / ${this.total}`
          : `${this.displayPage() + 1} / ${this.total}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
          .width(36)
          .height(36)
          .padding(6)
          .accessibilityText('阅读选项')
          .onClick(() => {
            this.showSettings = true;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    // 底部：靠图一侧透明 → 底部不透明（同一套渐变遮罩，边缘柔和）。
    .linearGradient({
      angle: 180,
      colors: [
        [$r('app.color.reader_chrome_clear'), 0],
        [$r('app.color.reader_chrome'), 1]
      ]
    })
  }

  /** 阅读选项 sheet：方向 / 转屏 / 常亮 / 本页（图标+短语行）。 */
  @Builder
  settingsSheet() {
    Column({ space: 4 }) {
      Text('方向')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      CapsuleSegmentButtonV2({
        items: new SegmentButtonV2Items(
          [{ text: '从左到右' }, { text: '从右到左' }, { text: '纵向' }]),
        selectedIndex: this.settings.readerDirection === ReadingDirection.LTR ? 0 :
          (this.settings.readerDirection === ReadingDirection.RTL ? 1 : 2),
        $selectedIndex: (index: number) => {
          this.setDirection(index === 0 ? ReadingDirection.LTR :
            (index === 1 ? ReadingDirection.RTL : ReadingDirection.VERTICAL));
        }
      })
      .width('100%')
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
        Text('转屏锁定')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.orientationLocked })
          .onChange(() => {
            this.toggleOrientationLock();
          })
      }
      .width('100%')
      .padding({ top: 8 })
      .alignItems(VerticalAlign.Center)
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.sun_max'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
        Text('常亮')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.keepScreenOn })
          .onChange((on: boolean) => {
            this.keepScreenOn = on;
            this.setKeepScreenOn(on);
          })
      }
      .width('100%')
      .padding({ top: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 24 })
  }

  build() {
    HdsNavDestination() {
      // 外层 Stack：底栏按 Bottom 对齐（只占自身高度）；内层 Stack：顶栏按 Top 对齐。
      // 关键：操作栏**不能**用「铺满全屏 + Blank + hitTestBehavior(None)」——
      // 那样 Blank 会成为命中目标，把图片/列表的触摸全吞掉（单击、滑动、双击都会失效）。
      Stack({ alignContent: Alignment.Bottom }) {
        Stack({ alignContent: Alignment.Top }) {
          // 内容层：铺满（不参与标题栏布局）；阅读器自成一套表面（纯白/纯黑）。
          Column() {
            if (this.total <= 0 || this.images.length < this.total) {
              if (this.ready) {
                Column({ space: 16 }) {
                  Text(this.message).fontSize(14).fontColor($r('app.color.text_secondary'))
                  // 失败态必须有出路：total=0 时顶/底栏都不渲染，没有这个按钮就只剩系统返回手势。
                  Button('重新加载')
                    .onClick(() => {
                      this.message = '';
                      this.ready = false;
                      this.init();
                    })
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
              } else {
                Column() {
                  LoadingProgress().width(48).height(48)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
              }
            } else if (this.settings.readerDirection === ReadingDirection.VERTICAL) {
              this.verticalList()
            } else {
              this.horizontalPager()
            }
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.reader_bg'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          // 顶栏：只占 56vp，浮在图片上方，存在/消失都不改变内容布局。
          if (this.total > 0 && this.chromeShown) {
            Column() {
              this.topBar()
            }
            .width('100%')
            .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
          }
        }
        .width('100%')
        .height('100%')

        // 底栏：按 Bottom 对齐，只占自身高度（中间区域触摸照常落到图片/列表）。
        if (this.total > 0 && this.chromeShown) {
          Column() {
            this.bottomBar()
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
        }
      }
      .width('100%')
      .height('100%')
    }
    // 阅读器不用 HDS 标题栏（会把内容压下去、切沉浸时整页重排）；返回走自己的覆盖式顶栏。
    .hideTitleBar(true)
    .bindSheet($$this.showSettings, this.settingsSheet(), {
      title: { title: '阅读选项' },
      systemMaterial: SHEET_MATERIAL
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
      const param: DetailParam | undefined = ctx.pathInfo.param as DetailParam | undefined;
      if (param === undefined) {
        Logger.error('Reader', 'reader opened without param');
        this.message = '缺少参数';
        this.ready = true;
        return;
      }
      this.gid = param.gid;
      this.token = param.token;
      this.startPage = param.startPage ?? -1;
      // 详情页已给总页数 → 首帧就有确定的分母与图片槽，不必等详情请求。
      this.pendingPages = param.pages !== undefined && param.pages > 0 ? param.pages : 0;
      this.init();
    })
    // 退出阅读即恢复窗口状态（常亮关、全屏退），不影响其他页面。
    // 先取消待触发的单击切换：否则 280ms 内退出会让定时器在页外把窗口切进沉浸，且无页面能恢复它。
    .onDisAppear(() => {
      this.cancelImmersiveSoon();
      this.setKeepScreenOn(false);
      if (this.immersive) {
        this.restoreWindow();
      }
      if (this.orientationLocked) {
        this.orientationLocked = false;
        window.getLastWindow(this.context()).then((win: window.Window) => {
          win.setPreferredOrientation(window.Orientation.AUTO_ROTATION_UNSPECIFIED).catch((e: object) => {
            Logger.error('Reader', `restore orientation failed: ${e}`);
          });
        }).catch((e: object) => {
          Logger.error('Reader', `restore orientation window failed: ${e}`);
        });
      }
    })
  }
}
