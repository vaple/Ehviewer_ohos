import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { AppStorageV2, CapsuleSegmentButtonV2, PersistenceV2, SegmentButtonV2Items, UIContext, window } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { GalleryDetail } from '../model/GalleryDetail';
import { GalleryPageResult } from '../parser/GalleryPageParser';
import { DetailParam } from '../model/DetailParam';
import { ReadingDirection, resolveStartPage, scrubTargetPage, toDisplayIndex, toPage } from '../reader/ReaderMode';
import { clampPrefetch, neighbors, range } from '../reader/PrefetchPlan';
import { TokenChunks } from '../reader/TokenChunks';
import { applyPinch, nextDoubleTapScale, panTranslate, clampOffset, IMMERSIVE_DELAY_MS, ZOOM_MIN, ZOOM_MAX, DOUBLE_TAP_SCALE } from '../reader/ZoomModel';
import { ImageStore } from '../service/ImageStore';
import { PreviewSpriteCache } from '../service/PreviewSpriteCache';
import { PreviewChunk, PreviewChunkStore } from '../service/PreviewChunkStore';
import { PreviewCell } from '../model/PreviewCell';
import { JumpStripCell } from './JumpStripCell';
import { chunkOfPage, chunksInRange } from '../common/JumpStrip';
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
import { READER_SHEET_H, TOUCH_MIN, sheetBackdrop } from './Materials';
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
            .fontColor([$r('sys.color.brand')])
          Text('重新加载')
            .fontSize(13)
            .fontColor($r('sys.color.brand'))
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
  /** 拖动胶片条：停稳 120ms 才取图；格宽上限 / 宽高比 / 间隙 / 内边距（与跳跃条带同节拍）。 */
  private static readonly SCRUB_SETTLE_MS: number = 120;
  private static readonly FILM_CELL_MAX_W: number = 78;
  private static readonly FILM_H_RATIO: number = 110 / 78;
  private static readonly FILM_GAP: number = 8;
  private static readonly FILM_PAD: number = 6;
  /** 格子下方页码行的高度（vp，10fp 字号；和 `JumpStripCell` 的占位/真图同高）。 */
  private static readonly FILM_TEXT_H: number = 16;
  /** 双击放大/复位的过渡时长（ms）：只给这两个动作，拖动/捏合必须逐帧跟手。 */
  private static readonly ZOOM_ANIM_MS: number = 260;

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
  /** 拖动胶片条的 5 格窗口（固定 5 槽；`page = -1` = 首/尾空槽，目标永远 index 2）。 */
  @Local filmCells: PreviewCell[] = [];
  /** 拖动缩略图：成品 PixelMap（私有 + ready 标记，沿 `PreviewCropCell` 的写法，别把 PixelMap 放进 @Local）/ 本地整页图兜底 / 滑杆容器宽度。 */
  private scrubThumbPm: image.PixelMap | null = null;
  @Local scrubThumbReady: boolean = false;
  @Local scrubThumbPage: number = -1;
  @Local scrubThumbUrl: string = '';
  @Local scrubBarW: number = 0;
  /** 底栏实测高度（vp）：胶片条挂在底栏上方的页面级 Stack 里，靠它定位。 */
  @Local bottomBarH: number = 0;
  /** 当前持有的精灵图缓存键（换页/退出时 release）。 */
  private scrubThumbKey: string = '';
  /** 停稳取图定时器（`-1` = 没有待触发）。 */
  private scrubTimer: number = -1;
  /** 取图代际：拖动/松手后作废在飞结果。 */
  private scrubGen: number = 0;
  private scrubCache: PreviewSpriteCache = new PreviewSpriteCache();
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
  /** `ImageFit.Contain` 实际绘制的图片尺寸（vp，来自 `Image.onComplete` 的 `contentWidth/Height`）。 */
  private contentW: number = 0;
  private contentH: number = 0;
  /** 页 token：分块取 + 同块并发去重（预取一次并发十几页，常有 4 个挤在同一个 chunk）。 */
  private tokenChunks: TokenChunks = new TokenChunks((chunk: number): Promise<string[]> => {
    return this.loadChunkTokens(chunk);
  }, ReaderPage.PREVIEW_PER_CHUNK);
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
  private listScroller: ListScroller = new ListScroller();
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
   * 单击切操作栏：延迟 `IMMERSIVE_DELAY_MS` 再执行（标准双击消歧，和 Android 的 double-tap-timeout 同构）。
   * 若期间来了双击，`cancelImmersiveSoon` 会取消它 —— 单击不会误触（延迟值的约束见常量注释）。
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
    }, IMMERSIVE_DELAY_MS);
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
        await client.getGalleryDetail(this.site, this.gid, this.token, this.settings.thumbSize);
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
      this.tokenChunks.seed(detail.previewTokens);
      // 详情首块自带缩略图：种进共享块缓存，拖动进度条到前 20 页时零请求出图。
      PreviewChunkStore.instance.seed(this.gid, 0, detail.previews);
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
    return await this.tokenChunks.ensure(page);
  }

  /** 拉某个预览分块的 pToken；与缩略图共用 `PreviewChunkStore`，同一块只发一条请求。 */
  private async loadChunkTokens(chunk: number): Promise<string[]> {
    const client: EhClient = await this.ensureClient();
    const gid: number = this.gid;
    const chunkData: PreviewChunk = await PreviewChunkStore.instance.ensure(gid, chunk,
      () => client.getPreviews(this.site, gid, this.token, chunk));
    return chunkData.tokens;
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
        this.tokenChunks.put(page + 1, result.nextPToken);
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

  /**
   * 平移夹取（屏幕 vp）：可移动范围按 `ImageFit.Contain` 的**实际绘制尺寸**算，不是容器尺寸。
   * 见 `ZoomModel.clampOffset` 的注释（真机实测：按容器夹取会拖出黑边）。
   */
  private clampOffsetX(offset: number, scale: number): number {
    return clampOffset(offset, this.viewW, this.contentW, scale);
  }

  private clampOffsetY(offset: number, scale: number): number {
    return clampOffset(offset, this.viewH, this.contentH, scale);
  }

  /**
   * 双击：放大到 `ZOOM_MAX` / 复位到 `ZOOM_MIN`，**带过渡动画**。
   *
   * 为什么不能只改 `@Local` 状态：`.scale()` / `.translate()` 没有动画时是瞬变 —— 真机表现就是
   * "闪现放大"。这里用显式动画 `animateTo`（与列表→详情共享元素转场同一条官方路径），
   * 只包住双击这一个动作：拖动/捏合仍在手势回调里逐帧改状态，不受影响。
   */
  private applyDoubleTap(): void {
    const next: number = nextDoubleTapScale(this.imgScale, DOUBLE_TAP_SCALE);
    if (next <= ZOOM_MIN) {
      this.getUIContext().animateTo({
        duration: ReaderPage.ZOOM_ANIM_MS, curve: Curve.Friction
      }, () => {
        this.imgScale = ZOOM_MIN;
        this.imgOffsetX = 0;
        this.imgOffsetY = 0;
      });
      return;
    }
    // 放大：重置偏移（居中），并把捏合/拖动基准对齐到新比例，否则下一步拖动会从旧基准跳一下。
    this.getUIContext().animateTo({
      duration: ReaderPage.ZOOM_ANIM_MS, curve: Curve.Friction
    }, () => {
      this.imgScale = next;
      this.pinchBase = next;
      this.imgOffsetX = 0;
      this.imgOffsetY = 0;
      this.panBaseX = 0;
      this.panBaseY = 0;
    });
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
      // `ImageFit.Contain` 的实际绘制尺寸（未缩放）：平移夹取必须按它算，否则留黑的轴上能拖出黑边。
      .onComplete((e) => {
        if (e === undefined) {
          return;
        }
        const w: number = px2vp(Number(e.contentWidth));
        const h: number = px2vp(Number(e.contentHeight));
        if (w > 0 && h > 0 && (w !== this.contentW || h !== this.contentH)) {
          this.contentW = w;
          this.contentH = h;
        }
      })
      // 双击放大/复位走显式动画（`animateTo`，见 `applyDoubleTap`）；拖动与捏合逐帧跟手，
      // 这里**不挂** `.animation()` —— 否则每次 `onActionUpdate` 都会排一遍过渡，拖动会明显发飘。
      // 并行竞技场 + 延迟消歧：单击走 `toggleImmersiveSoon`（延迟一拍后才切），
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
              const next: number = applyPinch(this.pinchBase, e.scale, ZOOM_MIN, ZOOM_MAX);
              // 缩放中心的补偿由 `scale` 的 `centerX/centerY`（默认 50%）承担，这里只夹取范围。
              // 注意当前偏移必须按**新**比例夹取：缩回 1 倍时范围收成 0，图片自动回中。
              this.imgScale = next;
              this.imgOffsetX = this.clampOffsetX(this.imgOffsetX, next);
              this.imgOffsetY = this.clampOffsetY(this.imgOffsetY, next);
            })
            .onActionEnd(() => {
              // 捏合结束把平移基准对齐到最终比例/偏移，下一次单指拖动才不会跳。
              this.pinchBase = this.imgScale;
              this.panBaseX = this.imgOffsetX;
              this.panBaseY = this.imgOffsetY;
            }),
          TapGesture({ count: 2, distanceThreshold: ReaderPage.TAP_SLOP })
            .onAction(() => {
              this.cancelImmersiveSoon();
              this.lastDoubleTap = Date.now();
              this.applyDoubleTap();
            }),
          // `fingers` 是**下限**（SDK 明文）：`PanGesture({fingers: 1})` 在双指时照样触发，
          // 而多指时 `onActionUpdate` 只跟其中**一根**手指（SDK：updates the location information
          // of only one finger each time）→ 捏合/张开时它会把偏移写偏，表现为画面突然跳一小段。
          // `isFingerCountLimited: true` 强制「手指数必须精确等于 fingers」，双指时 Pan 不参与。
          PanGesture({ fingers: 1, distance: 10, isFingerCountLimited: true })
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
              // 回调偏移在局部坐标里（含 `scale()`），换算回屏幕 vp 再夹取，否则拖动慢 `scale` 倍。
              this.imgOffsetX = this.clampOffsetX(
                this.panBaseX + panTranslate(e.offsetX, this.imgScale), this.imgScale);
              this.imgOffsetY = this.clampOffsetY(
                this.panBaseY + panTranslate(e.offsetY, this.imgScale), this.imgScale);
            })
        )
      )
  }

  /** `Swiper.index` 用 `$$` 双向绑定（它不在 `!!` 支持表内），所以这里不再手写 `this.index = i`。 */
  private onIndexChange(i: number): void {
    if (this.total <= 0) {
      return;
    }
    // 滑动（`onIndexChange` 只由 `Swiper.onChange` 触发）时取消待触发的单击切换：点按后延迟窗口内滑动不再附带切沉浸。
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

  /** 滑杆显示索引 → 实际页号；未拖动 / 无页返回 -1。 */
  private scrubTarget(): number {
    if (this.scrubPage < 0 || this.total <= 0) {
      return -1;
    }
    return scrubTargetPage(this.scrubPage, this.total, this.settings.readerDirection);
  }

  /** 取消待触发的停稳取图，并让在飞结果作废。 */
  private cancelScrubThumb(): void {
    if (this.scrubTimer >= 0) {
      clearTimeout(this.scrubTimer);
      this.scrubTimer = -1;
    }
    this.scrubGen += 1;
  }

  /** 拖动停稳 120ms 后才取目标块（与跳页条带同一节拍）。 */
  private scheduleScrubThumb(): void {
    this.cancelScrubThumb();
    const gen: number = this.scrubGen;
    this.scrubTimer = setTimeout(() => {
      this.scrubTimer = -1;
      this.loadScrubThumb(gen).catch((e: object) => {
        Logger.error('Reader', `scrub thumb failed: ${e}`);
      });
    }, ReaderPage.SCRUB_SETTLE_MS);
  }

  /** 取目标页缩略图：先填 5 格窗口，再给中间格取 sprite → 本地整页图 → 窗口块。 */
  private async loadScrubThumb(gen: number): Promise<void> {
    const page: number = this.scrubTarget();
    // total 在系统栏切完 / 详情回来后可能变化：越界的旧 scrubPage 不能索引 images。
    if (page < 0 || page >= this.total || page >= this.images.length) {
      return;
    }
    this.fillFilmCells();
    const chunk: number = chunkOfPage(page);
    let cell: PreviewCell | undefined = this.findPreviewCell(
      PreviewChunkStore.instance.peek(this.gid, chunk), page);
    if (cell === undefined) {
      const local: string = this.images[page].url;
      if (local.length > 0) {
        if (gen === this.scrubGen && this.scrubPage >= 0 && this.scrubTarget() === page) {
          this.showScrubUrl(page, local);
          Logger.info('Reader', `scrub thumb page=${page + 1} source=local`);
        }
        return;
      }
      // 冷却中的块直接跳过：不重复发请求，也不重复打日志（与详情网格同口径）。
      if (PreviewChunkStore.instance.failedRecently(this.gid, chunk)) {
        return;
      }
      const client: EhClient = await this.ensureClient();
      // 窗口覆盖的块（最多 3 块）一起取：左右格跨块时也不空窗；同块由 store single-flight。
      const pages: number[] = this.filmPages();
      let minPage: number = page;
      let maxPage: number = page;
      for (let i = 0; i < pages.length; i++) {
        if (pages[i] < minPage) {
          minPage = pages[i];
        }
        if (pages[i] > maxPage) {
          maxPage = pages[i];
        }
      }
      const chunkIds: number[] = chunksInRange(minPage, maxPage, this.total);
      const tasks: Promise<PreviewChunk>[] = [];
      for (let i = 0; i < chunkIds.length; i++) {
        const c: number = chunkIds[i];
        if (PreviewChunkStore.instance.failedRecently(this.gid, c)) {
          continue;
        }
        tasks.push(PreviewChunkStore.instance.ensure(this.gid, c,
          () => client.getPreviews(this.site, this.gid, this.token, c)));
      }
      await Promise.all(tasks);
      if (gen !== this.scrubGen || this.scrubPage < 0 || this.scrubTarget() !== page) {
        return;
      }
      this.fillFilmCells();
      cell = this.findPreviewCell(PreviewChunkStore.instance.peek(this.gid, chunk), page);
    }
    if (cell === undefined || cell.url.length === 0) {
      return;
    }
    if (gen !== this.scrubGen || this.scrubPage < 0) {
      return;
    }
    const client: EhClient = await this.ensureClient();
    const key: string = PreviewSpriteCache.keyOf(cell.url, cell.x, cell.y, cell.w, cell.h);
    let pm: image.PixelMap;
    try {
      pm = await this.scrubCache.acquire(this.context(), client,
        EhUrl.referer(this.site), cell.url, cell.x, cell.y, cell.w, cell.h);
    } catch (e) {
      // 精灵图失败（离线 / 限流）：退回本地整页图，别让已缓存的页卡在占位。
      Logger.error('Reader', `scrub sprite failed page=${page + 1}: ${e}`);
      if (gen === this.scrubGen && this.scrubPage >= 0 && this.scrubTarget() === page) {
        const local: string = this.images[page].url;
        if (local.length > 0) {
          this.showScrubUrl(page, local);
          Logger.info('Reader', `scrub thumb page=${page + 1} source=local-fallback`);
        }
      }
      return;
    }
    if (gen !== this.scrubGen || this.scrubPage < 0 || this.scrubTarget() !== page) {
      PreviewSpriteCache.release(key);
      return;
    }
    this.releaseScrubThumb();
    this.scrubThumbKey = key;
    this.scrubThumbPm = pm;
    this.scrubThumbReady = true;
    this.scrubThumbPage = page;
    this.scrubThumbUrl = '';
    Logger.info('Reader', `scrub thumb page=${page + 1} source=sprite`);
  }

  /** 5 格窗口覆盖的实际页（不含首尾空槽）。 */
  private filmPages(): number[] {
    const pages: number[] = [];
    if (this.scrubPage < 0 || this.total <= 0) {
      return pages;
    }
    for (let i = -2; i <= 2; i++) {
      const display: number = this.scrubPage + i;
      if (display < 0 || display >= this.total) {
        continue;
      }
      pages.push(scrubTargetPage(display, this.total, this.settings.readerDirection));
    }
    return pages;
  }

  /** 重建 5 格窗口：目标固定 index 2；首尾越界留空槽（page = -1）；值只来自 store 缓存。 */
  private fillFilmCells(): void {
    if (this.scrubPage < 0 || this.total <= 0) {
      this.filmCells = [];
      return;
    }
    const cells: PreviewCell[] = [];
    for (let i = -2; i <= 2; i++) {
      const display: number = this.scrubPage + i;
      if (display < 0 || display >= this.total) {
        const empty: PreviewCell = new PreviewCell();
        empty.page = -1;
        cells.push(empty);
        continue;
      }
      const page: number = scrubTargetPage(display, this.total, this.settings.readerDirection);
      const found: PreviewCell | undefined = this.findPreviewCell(
        PreviewChunkStore.instance.peek(this.gid, chunkOfPage(page)), page);
      if (found !== undefined) {
        cells.push(found);
      } else {
        const placeholder: PreviewCell = new PreviewCell();
        placeholder.page = page;
        cells.push(placeholder);
      }
    }
    this.filmCells = cells;
  }

  /** 左右格的精灵图（`PreviewCropCell` 负责引用计数；失败返回 null 并记日志）。 */
  private async scrubSprite(cell: PreviewCell): Promise<image.PixelMap | null> {
    if (cell.url.length === 0) {
      return null;
    }
    try {
      const client: EhClient = await this.ensureClient();
      return await this.scrubCache.acquire(this.context(), client, EhUrl.referer(this.site),
        cell.url, cell.x, cell.y, cell.w, cell.h);
    } catch (e) {
      Logger.error('Reader', `scrub sprite failed page=${cell.page + 1}: ${e}`);
      return null;
    }
  }

  /** 在块里找目标页（`PreviewCell.url` 为空视为没有预览）。 */
  private findPreviewCell(chunk: PreviewChunk | undefined, page: number): PreviewCell | undefined {
    if (chunk === undefined) {
      return undefined;
    }
    for (let i = 0; i < chunk.cells.length; i++) {
      if (chunk.cells[i].page === page && chunk.cells[i].url.length > 0) {
        return chunk.cells[i];
      }
    }
    return undefined;
  }

  /** 本地整页图兜底（已下载 / 已缓存）：先释放旧精灵图引用。 */
  private showScrubUrl(page: number, url: string): void {
    this.releaseScrubThumb();
    this.scrubThumbPm = null;
    this.scrubThumbReady = false;
    this.scrubThumbPage = page;
    this.scrubThumbUrl = url;
  }

  /** 释放当前精灵图引用（键为空时无操作）。 */
  private releaseScrubThumb(): void {
    if (this.scrubThumbKey.length > 0) {
      PreviewSpriteCache.release(this.scrubThumbKey);
      this.scrubThumbKey = '';
    }
  }

  private clearScrubThumb(): void {
    this.releaseScrubThumb();
    this.scrubThumbPm = null;
    this.scrubThumbReady = false;
    this.scrubThumbPage = -1;
    this.scrubThumbUrl = '';
  }

  /** 格宽按容器算：min(78, (bar - 4*gap - 2*pad) / 5)，不按机型写死。 */
  private filmCellW(): number {
    const available: number = this.scrubBarW > 0 ? this.scrubBarW : 320;
    const raw: number = (available - 4 * ReaderPage.FILM_GAP - 2 * ReaderPage.FILM_PAD) / 5;
    return Math.max(40, Math.min(ReaderPage.FILM_CELL_MAX_W, raw));
  }

  private filmCellH(): number {
    return this.filmCellW() * ReaderPage.FILM_H_RATIO;
  }

  private filmSlotH(): number {
    return this.filmCellH() + ReaderPage.FILM_TEXT_H;
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
          .fontColor([$r('sys.color.brand')])
        Text('重新加载')
          .fontSize(13)
          .fontColor($r('sys.color.brand'))
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
    // 纵向列表**不做缩放**（双击放大与捏合都已移除，见 #73 的结论）。
    //
    // 为什么不把缩放挂在这一层：`Scroll.zoomScale` 会把整棵 `List` 一起放大，于是
    //   1) 外层 `Scroll` 获得可滚区间、抢走内层 `List` 的单指滚动（`onScrollIndex` 停摆）；
    //   2) 内层 `List` 收到的手势位移是被缩放过的局部坐标（实测 1/4），拖动变慢；
    //   3) 横轴一个接收者都没有（外层 PAN 被禁），放大后左右拖完全无响应。
    // 而「另开一个只含单图的看图层」也没能救回来（长条漫用 `Contain` 会反而变小、
    // 双击过渡必然闪、缩回 1× 还停在单图态卡边缘）—— 详见 #73。条漫整宽显示本来就不需要放大。
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
    .height('100%')
    // 单击走延迟切换，与横向阅读同一套消歧（`lastDoubleTap` 已随纵向放大一起移除）。
    // `distanceThreshold` 必须给，否则滑动会被吞成点击（默认阈值是 2^31-1）。
    //
    // 纵向**不做双击放大、也不做捏合**：这是刻意的取舍，理由见 `verticalList` 开头那段。
    .gesture(
      TapGesture({ count: 1, distanceThreshold: ReaderPage.TAP_SLOP })
        .onAction(() => {
          this.toggleImmersiveSoon();
        })
    )
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
      // 底色用与两侧**同一个** `reader_btn_bg`：安全控件会把 alpha < 0x1A 的底色强制拉到 0xFF
      // （SDK `security_component.d.ts` 明文），所以浅色那份取 #1C000000（alpha 0x1C > 0x1A）——
      // 既保留半透明光感，又不会被系统拉成纯黑方块。
      SaveButton({ icon: SaveIconStyle.LINES, buttonType: ButtonType.Circle })
        .userCancelEvent(true)
        .iconSize(20)
        .iconColor($r('app.color.text_primary'))
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.reader_btn_bg'))
        .borderWidth(1)
        .borderColor($r('app.color.reader_btn_ring'))
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
      Stack({ alignContent: Alignment.TopStart }) {
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
              // 拖动中只跟手 + 重建 5 格窗口（只用已缓存 cells），停稳 120ms 才取块。
              this.scrubPage = v;
              this.fillFilmCells();
              this.scheduleScrubThumb();
              return;
            }
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.cancelScrubThumb();
              this.scrubPage = -1;
              this.clearScrubThumb();
              this.filmCells = [];
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
      }
      .width('100%')
      .clip(false)
      .onAreaChange((_old: Area, now: Area) => {
        const w: number = Number(now.width);
        if (w !== this.scrubBarW) {
          this.scrubBarW = w;
        }
      })
      Row({ space: 8 }) {
        // 页码是确定性的：分母来自详情（`DetailParam.pages`）；拖动时按实际页显示（RTL 也一致）。
        Text(this.scrubPage >= 0
          ? `${this.scrubTarget() + 1} / ${this.total}`
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
          .id('reader-settings')
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
          .onAreaChange((_old: Area, now: Area) => {
            const h: number = Number(now.height);
            if (h !== this.bottomBarH) {
              this.bottomBarH = h;
            }
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
        }
        // 拖动胶片条：5 格、目标固定 index 2；首尾缺页留空槽。挂在页面级 Stack，避免父容器裁剪。
        if (this.total > 0 && this.chromeShown && this.scrubPage >= 0
          && this.filmCells.length === 5) {
          Row({ space: ReaderPage.FILM_GAP }) {
            ForEach(this.filmCells, (cell: PreviewCell, index: number) => {
              if (index === 2) {
                // 中间格：目标页；高亮边框；保留本地整页图兜底。
                Column({ space: 2 }) {
                  if (this.scrubThumbReady && this.scrubThumbPage === this.scrubTarget()
                    && this.scrubThumbPm !== null) {
                    Image(this.scrubThumbPm)
                      .width('100%')
                      .height(this.filmCellH())
                      .objectFit(ImageFit.Cover)
                      .borderRadius(6)
                  } else if (this.scrubThumbUrl.length > 0
                    && this.scrubThumbPage === this.scrubTarget()) {
                    Image(this.scrubThumbUrl)
                      .width('100%')
                      .height(this.filmCellH())
                      .objectFit(ImageFit.Cover)
                      .borderRadius(6)
                  } else {
                    Column()
                      .width('100%')
                      .height(this.filmCellH())
                      .borderRadius(6)
                      .backgroundColor($r('app.color.bg_secondary'))
                  }
                  Text(`${this.scrubTarget() + 1}`)
                    .fontSize(10)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                }
                .width(this.filmCellW())
                // 目标格靠“居中位置 + 页码 + 底栏 X / N”标识；不套边框：边框会随 ForEach 重建闪，
                // 且 padding/border 让中间格比邻格宽 6vp。
              } else if (cell.page >= 0) {
                JumpStripCell({
                  cell: cell,
                  cellW: this.filmCellW(),
                  cellH: this.filmCellH(),
                  spriteOf: (c: PreviewCell) => this.scrubSprite(c)
                })
              } else {
                // 首/尾缺页：同宽同高空槽，目标格仍居中。
                Column()
                  .width(this.filmCellW())
                  .height(this.filmSlotH())
              }
            }, (cell: PreviewCell, index: number) =>
              cell.page >= 0 ? `p${cell.page}:${cell.url}` : `e${index}`)
          }
          .padding(ReaderPage.FILM_PAD)
          .borderRadius(14)
          // 内容区浮层拿不到系统材质（ui/AGENTS.md #67）。
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .hitTestBehavior(HitTestMode.None)
          .id('reader-scrub-film')
          .margin({ bottom: this.bottomBarH + ReaderPage.FILM_GAP })
          .transition(TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.EaseInOut }))
        }
      }
      .width('100%')
      .height('100%')
    }
    // 阅读器不用 HDS 标题栏（会把内容压下去、切沉浸时整页重排）；返回走自己的覆盖式顶栏。
    .hideTitleBar(true)
    .bindSheet($$this.showSettings, this.settingsSheet(), {
      title: { title: '阅读选项' },
      // 默认挡位是 LARGE（近全屏），这 3 行设置会剩一大片空白（真机 `FIT_CONTENT` 不生效，见 READER_SHEET_H）。
      detents: [READER_SHEET_H],
      // 半模态材质必须组件级设置（应用级开关不覆盖 `bindSheet`，见 `Materials.ets`）。
      backgroundColor: sheetBackdrop().backgroundColor,
      systemMaterial: sheetBackdrop().material,
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
    // 先取消待触发的单击切换：否则延迟窗口内退出会让定时器在页外把窗口切进沉浸，且无页面能恢复它。
    .onDisAppear(() => {
      this.cancelScrubThumb();
      this.clearScrubThumb();
      this.filmCells = [];
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
