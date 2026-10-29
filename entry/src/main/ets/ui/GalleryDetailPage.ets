import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { PersistenceV2, promptAction, ChipV2, ChipV2Label, ChipV2Options, ChipV2Size, ColorMetrics, LengthMetrics, SymbolGlyphModifier, SubHeaderV2, SubHeaderV2Title } from '@kit.ArkUI';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { ImageStore } from '../service/ImageStore';
import { RateResult } from '../network/EhApi';
import { Logger } from '../common/Logger';
import { hapticTap } from '../common/Haptic';
import { setDiagContext } from '../service/CrashCollector';
import { GalleryDetail } from '../model/GalleryDetail';
import { GalleryComment } from '../model/GalleryComment';
import { TagGroup } from '../model/TagGroup';
import { PreviewItem } from '../model/PreviewItem';
import { DetailParam, DetailPreview } from '../model/DetailParam';
import { displayRatingFor, shouldSubmitRating } from '../model/GalleryRating';
import { SearchParam } from '../model/SearchParam';
import { HistoryDao } from '../db/dao/HistoryDao';
import { HistoryInfo } from '../model/HistoryInfo';
import { FilterDao } from '../db/dao/FilterDao';
import { Filter } from '../model/Filter';
import { qualifyTag, exactTagQuery } from '../search/SearchQuery';
import { DbHelper } from '../db/DbHelper';
import { FavCatSheet, FavCatOption } from './FavCatSheet';
import { PreviewCropCell } from './PreviewCropCell';
import { PreviewSpriteCache } from '../service/PreviewSpriteCache';
import { AppSettings } from '../state/AppSettings';
import { ReadingProgressStore } from '../state/ReadingProgressStore';
import { AppStorageV2 } from '@kit.ArkUI';
import { WindowState } from '../state/WindowState';
import { HdsActionBar, ActionBarButton, ActionBarStyle, HdsNavDestination, BlurStrategy, ScrollEffectType } from '@kit.UIDesignKit';
import { CATEGORY_UNKNOWN, languageOf } from '../parser/ParserUtils';
import { tagQueryOf, GalleryDetailParser } from '../parser/GalleryDetailParser';
import { errorText } from '../common/ErrorText';
import { catColor, catLabel } from './CategoryStyle';
import { CARD_RADIUS, ACTION_BAR_BTN_H, ACTION_BAR_H, ACTION_BAR_MARGIN, HDS_MATERIAL, JUMP_SHEET_H, PAGE_PADDING, SHEET_MATERIAL, THUMB_RADIUS, TOUCH_MIN, commentScoreColor } from './Materials';
import { commentDateText, commentScoreText } from '../common/CommentText';
import { galleryGeometryId } from './GalleryRow';
import { SkeletonBlock } from './Skeleton';
import { TITLE_BAR_H } from './NavStyle';
import { downloadManager } from '../service/DownloadManager';
import { DownloadItem, DownloadQuality, DownloadState } from '../model/DownloadRecord';
import { DownloadDao } from '../db/dao/DownloadDao';
import { QuotaLine } from './QuotaLine';
import { PreviewCell } from '../model/PreviewCell';
import { JumpSheet } from './JumpSheet';

/** 骨架屏预览占位格数（2 行 × 3 列，与真实网格同列宽）。 */
const SKELETON_PREVIEW_CELLS: number[] = [0, 1, 2, 3, 4, 5];

/** 底部动作条自动收起的滚动阈值（vp）：滚过标题区才开始收，避免顶部轻扫就躲。 */
const BAR_HIDE_AFTER: number = 240;
/** 判定「一次滚动」的最小位移（vp）：小于它视为抖动，不切换收起/展开。 */
const BAR_HIDE_DELTA: number = 8;
/** 动作条主按钮内：图标尺寸 / 图标与数字间距 / 左右内边距（vp）。 */
const READ_PILL_ICON: number = 20;
const READ_PILL_GAP: number = 8;
const READ_PILL_PAD: number = 16;
/** 16fp 等宽数字的单字符宽度（vp）：官方主按钮槽只收显式宽度，只能按位数估算。 */
const READ_PILL_DIGIT: number = 9.6;

/** 标签 chip：点按搜索；长按菜单二选（搜索 / 屏蔽此标签）。点按语义与原来一致。 */
@ComponentV2
struct TagChip {
  @Require @Param ns: string;
  @Require @Param tag: string;
  @Event onSearch: (ns: string, tag: string) => void = (_ns: string, _tag: string) => {};
  @Event onBlock: (ns: string, tag: string) => void = (_ns: string, _tag: string) => {};
  @Event onExcludeSearch: (ns: string, tag: string) => void = (_ns: string, _tag: string) => {};
  @Event onCopy: (ns: string, tag: string) => void = (_ns: string, _tag: string) => {};

  @Builder
  tagMenu() {
    Menu() {
      MenuItem({ content: '搜索' })
        .onClick(() => {
          this.onSearch(this.ns, this.tag);
        })
      MenuItem({ content: '从本次搜索排除' })
        .onClick(() => {
          this.onExcludeSearch(this.ns, this.tag);
        })
      MenuItem({ content: '加入搜索排除' })
        .onClick(() => {
          this.onBlock(this.ns, this.tag);
        })
      MenuItem({ content: '复制标签内容' })
        .onClick(() => {
          this.onCopy(this.ns, this.tag);
        })
    }
  }

  build() {
    // 官方 ChipV2（应用级材质开启后自带系统样式）；长按菜单挂在外层 Row（自定义组件的属性链挂不了通用属性）。
    Row() {
      ChipV2({
        chipV2Options: new ChipV2Options({
          label: new ChipV2Label({ text: this.tag, fontSize: LengthMetrics.fp(12) }),
          size: ChipV2Size.SMALL,
          allowClose: false,
          onClicked: () => {
            this.onSearch(this.ns, this.tag);
          }
        })
      })
    }
    .margin(4)
    // `onAppear` = 菜单真正弹出来那一刻 → 轻振一次（长按被识别的确认，与菜单动画同步；点按不受影响）。
    .bindContextMenu(this.tagMenu, ResponseType.LongPress, { onAppear: () => hapticTap() })
  }
}

/** 详情页。参数经 `NavDestination.onReady(ctx)` 的 `ctx.pathInfo.param` 传入。 */
@ComponentV2
export struct GalleryDetailPage {
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  /** 系统安全区（详情内容顶部避让 = safeTop + 标题栏高）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  @Local gid: number = 0;
  private token: string = '';
  @Local title: string = '';
  @Local category: number = CATEGORY_UNKNOWN;
  @Local uploader: string = '';
  @Local rating: number = 0;
  @Local ratingCount: number = 0;
  @Local myRating: number = 0;
  @Local ratingBusy: boolean = false;
  @Local pages: number = 0;
  @Local tagGroups: TagGroup[] = [];
  /** 封面：`thumbUrl` 远端地址（`detail.thumb`），`thumb` 落盘后的本地 URI（`Image` 渲染用；沿 `GalleryRowItem` 命名）。 */
  @Local thumbUrl: string = '';
  @Local thumb: string = '';
  /** 预览格（首块随详情自带，后块滚动按需追加）。 */
  @Local previewCells: PreviewCell[] = [];
  /** 预览区几何（滚动预取估算用；仅作取块启发，不影响渲染精度）。 */
  private gridTopY: number = 0;
  private gridHeight: number = 0;
  private lastPrefRow: number = -1;
  /** 已载页（可视窗缺页判定用）。 */
  private loadedPages: Set<number> = new Set<number>();
  /** 已载最大页（滚到底追加下一块的起点；只往前，不回头补跳过的远端）。 */
  private maxLoadedPage: number = -1;
  /** 在飞分块（同块并发合并）。 */
  private chunkInflight: Set<number> = new Set<number>();
  /** 取空过的分块（不再重打）。 */
  private chunkDone: Set<number> = new Set<number>();
  private spriteCache: PreviewSpriteCache = new PreviewSpriteCache();
  private spriteClient: EhClient | undefined = undefined;
  private spriteGid: number = -1;
  private spriteReferer: string = '';
  @Local comments: GalleryComment[] = [];
  @Local showSheet: boolean = false;
  /**
   * 半模态内容：1 = 收藏夹，2 = 下载，3 = 跳页。
   * 同一次只能挂一个半模态（同一节点挂两个 `bindSheet` 会静默失效），所以用 kind 切内容，不要并列写多个。
   */
  @Local sheetKind: number = 0;
  /** 下载画质 + 忙碌态。 */
  @Local dlQuality: number = DownloadQuality.ORIGINAL;
  @Local dlBusy: boolean = false;
  @Local message: string = '';
  /** 收藏态（详情 `#gdf`；收藏成功即时改态，不必重进页面）。 */
  @Local isFavorited: boolean = false;
  @Local favoriteName: string = '';
  /** 收藏夹元信息（打开半模态前拉一次；空 = 未拉）。 */
  @Local favCats: string[] = [];
  @Local favCounts: number[] = [];
  private favMetaLoaded: boolean = false;
  /** 详情数据（`@Local`：`build` 里的 `data === null` 分支必须能因它变化而重算）。 */
  @Local data: GalleryDetail | null = null;
  /** 该画廊的阅读进度（0 起；`-1` = 没读过）。进页与从阅读器返回时各刷一次。 */
  @Local progressPage: number = -1;
  /** 底部动作条是否收起（向下滚动时收起、向上滚动时回来，避免长期压住预览网格）。 */
  @Local barHidden: boolean = false;
  /** 跳页半模态选中的页（0 起；`-1` = 没选）。等 sheet 退场后再进阅读器，避免两套转场叠在一起。 */
  private pendingJumpPage: number = -1;
  private lastScrollY: number = 0;
  private progress: ReadingProgressStore = PersistenceV2.globalConnect({
    type: ReadingProgressStore,
    key: 'ReadingProgressStore',
    defaultCreator: () => new ReadingProgressStore()
  })!;
  private pageStack: NavPathStack | undefined = undefined;
  /** 详情滚动器（标题栏渐变模糊要 `bindToScrollable` 才跟着内容走）。 */
  private scroller: Scroller = new Scroller();

  /**
   * 星条显示值：打过分为我的分，否则为平均分。
   * `Rating.onChange` 里与它相等即视为程序化赋值（详情 0 → 均值、评分回填）→ 忽略，不误打分。
   */
  @Computed get displayRating(): number {
    return displayRatingFor(this.myRating, this.rating);
  }

  /**
   * 底部动作条的主按钮文案：**`已读/总数`**，未读为 `0/总数`。
   * 不写「继续阅读」——动作由图标承载；数字是这本书唯一会变的状态。
   */
  @Computed get readLabel(): string {
    if (this.pages <= 0) {
      return '';
    }
    const page: number = this.progressPage < 0 ? 0 : this.progressPage + 1;
    return `${page}/${this.pages}`;
  }

  /** 主按钮没有可见动词，读屏文案补上动作与位置（`0/280` 读不出来是干什么的）。 */
  private readLabelA11y(): string {
    if (this.progressPage < 0) {
      return `开始阅读，共 ${this.pages} 页`;
    }
    return `继续阅读，第 ${this.progressPage + 1} 页，共 ${this.pages} 页`;
  }

  /** 主按钮宽度：官方 `primaryButtonBuilderWidth` 不接受百分比，只能按「图标 + 数字位数」算出来。 */
  @Computed get readPillWidth(): number {
    return READ_PILL_ICON + READ_PILL_GAP + this.readLabel.length * READ_PILL_DIGIT + READ_PILL_PAD * 2;
  }

  /** 动作条主按钮：图标 + 页码（官方动作条只给圆形图标位，文字要走自定义主按钮槽）。 */
  @Builder
  readPill() {
    Row({ space: READ_PILL_GAP }) {
      SymbolGlyph($r('sys.symbol.flipping_page'))
        .fontSize(READ_PILL_ICON)
        .fontColor([Color.White])
      Text(this.readLabel)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        // 等宽数字：0/280 → 12/280 时按钮宽度不抖。
        .fontFeature('"tnum" on')
    }
    .width(this.readPillWidth)
    .height(ACTION_BAR_BTN_H)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.brand'))
    .borderRadius(ACTION_BAR_BTN_H / 2)
    // 官方点击回弹：主按钮是自建内容，动作条只负责背板，不会替它加按压态。
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .accessibilityText(this.readLabelA11y())
    .id('detail-read')
    .onClick(() => {
      this.openReader();
    })
  }

  /** 进阅读器；`startPage < 0` 表示走进度恢复（阅读器自己读 `ReadingProgressStore`）。 */
  private openReader(startPage: number = -1): void {
    if (this.pages <= 0) {
      return;
    }
    const param: DetailParam = { gid: this.gid, token: this.token, pages: this.pages };
    if (startPage >= 0) {
      param.startPage = startPage;
    }
    this.pageStack?.pushPathByName('阅读', param);
  }

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  /** 读一次该画廊的阅读进度（进页 / 从阅读器返回 / 本地恢复时刷新入口文案）。 */
  private refreshProgress(): void {
    if (this.gid <= 0) {
      return;
    }
    this.progressPage = this.progress.load(this.gid);
  }

  private async load(): Promise<void> {
    setDiagContext(`page=detail gid=${this.gid}`);
    try {
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);

      const detail: GalleryDetail | null =
        await client.getGalleryDetail(site, this.gid, this.token, this.settings.thumbSize);
      this.data = detail;
      if (detail !== null) {
        this.title = detail.title;
        this.category = detail.category;
        this.uploader = detail.uploader;
        this.rating = detail.rating;
        this.ratingCount = detail.ratingCount;
        this.pages = detail.pages;
        this.tagGroups = detail.tagGroups;
        this.comments = detail.comments;
        this.isFavorited = detail.isFavorited;
        this.favoriteName = detail.favoriteName;
        this.message = '';
        // 封面：同 URL 且已有本地缓存（列表快照）则保留，避免详情回来瞬间闪回占位。
        const coverCached: boolean = this.thumb.length > 0 && this.thumbUrl === detail.thumb;
        this.thumbUrl = detail.thumb;
        if (!coverCached) {
          this.thumb = '';
          this.loadCover(detail.gid, detail.thumb);
        }
        this.setPreviews(detail.previews);
        this.recordHistory(detail).catch((e: object) => {
          Logger.error('Db', `history put failed gid=${detail.gid}: ${e}`);
        });
      } else {
        this.message = errorText(null, GalleryDetailParser.lastReason());
      }
    } catch (e) {
      Logger.error('Detail', `load failed gid=${this.gid}: ${e}`);
      this.message = errorText(e as Object);
    }
  }

  /**
   * 返回：共享元素反向衔接。push/pop 都关闭系统默认转场（`animated=false`），
   * 反向动画完全由 `animateTo` + 列表缩略图/详情封面的同 id 绑定承担。
   */
  private popAnimated(): void {
    const stack: NavPathStack | undefined = this.pageStack;
    if (stack === undefined) {
      return;
    }
    this.getUIContext().animateTo({ duration: 350, curve: Curve.EaseInOut }, () => {
      stack.pop(false);
    });
  }

  /** 封面下载（`GalleryRow.loadMissingThumbs` 同头：Cookie/Referer 落盘）。无封面直接回（常态，不记日志）；失败只记日志，不挡详情渲染。 */
  private async loadCover(gid: number, url: string): Promise<void> {
    if (url.length === 0) {
      return;
    }
    try {
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      const store: ImageStore = new ImageStore();
      await store.init(this.context());
      const local: string = await store.get(client, url, EhUrl.referer(site));
      if (this.gid === gid) {
        this.thumb = local;
      }
    } catch (e) {
      Logger.error('Detail', `cover failed gid=${gid}: ${e}`);
    }
  }

  /** 一键加入搜索排除（`term` 是完整查询词，如 `ns:tag` / `uploader:名字`）。 */
  private confirmBlock(term: string, display: string, label: string): void {
    if (term.length === 0) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '加入搜索排除',
      message: `以后每次搜索都会自动排除${label}「${display}」（列表本身不会隐藏）。`,
      buttons: [{ text: '再想想', color: '#8C8C8C' }, { text: '确定', color: '#3D6BE5' }]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.addBlockRule(term);
      }
    }).catch((_e: object) => {
      // 对话框自身失败不影响详情
    });
  }

  private async addBlockRule(term: string): Promise<void> {
    try {
      await DbHelper.init(this.context());
      const rule: Filter = { id: 0, mode: 0, text: qualifyTag(term), enable: true };
      await FilterDao.add(rule);
      promptAction.showToast({ message: '已加入搜索排除' });
    } catch (e) {
      Logger.error('Block', `add rule failed: ${e}`);
      promptAction.showToast({ message: '添加失败，请重试' });
    }
  }

  /** 从本次搜索排除（把 `-tag` 写进搜索框，不写库；同样用精确语法，避免误排 slave/长词）。 */
  private openTagExcludeSearch(namespace: string, tag: string): void {
    const raw: string = tagQueryOf(namespace, tag);
    const param: SearchParam = {
      query: `-${exactTagQuery(raw)}`,
      title: `排除 ${raw}`,
      kind: 'keyword'
    };
    this.pageStack?.pushPathByName('搜索', param);
  }

  /** 复制标签内容（`namespace:tag`），方便手动拼多标签查询。 */
  private async copyTagText(text: string): Promise<void> {
    try {
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: '标签已复制' });
    } catch (e) {
      Logger.error('Detail', `copy tag failed: ${e}`);
      promptAction.showToast({ message: '复制失败，请重试' });
    }
  }

  /**
   * 标签搜索（点按与长按菜单共用；长按另给屏蔽入口，点按语义不变）。
   * 查询串必须写成站点正规语法 `namespace:"tag$"`（引号并空格值、`$` 锚整词，源 `wrapTagKeyword`）：
   * 裸 `parody:blue archive` 既会被搜索框当成两个词拆 chip，`parody:blue` 也会命中 slave/长词标签。
   * 标题仍用人话原串，不把语法符号摆到标题上。
   */
  private openTagSearch(namespace: string, tag: string): void {
    const raw: string = tagQueryOf(namespace, tag);
    const param: SearchParam = {
      query: exactTagQuery(raw),
      title: `标签 ${raw}`,
      kind: 'tag'
    };
    this.pageStack?.pushPathByName('搜索', param);
  }
  /** 详情打开即记历史（真正的隔离边界：失败只记日志，不挡详情渲染）。 */
  private async recordHistory(d: GalleryDetail): Promise<void> {
    await DbHelper.init(this.context());
    const langTags: string[] = [];
    for (let i = 0; i < d.tagGroups.length; i++) {
      for (let j = 0; j < d.tagGroups[i].tags.length; j++) {
        langTags.push(`${d.tagGroups[i].namespace}:${d.tagGroups[i].tags[j]}`);
      }
    }
    const lang: string = languageOf(langTags);
    const info: HistoryInfo = {
      gid: d.gid, token: d.token, title: d.title, titleJpn: d.titleJpn, thumb: d.thumb,
      category: d.category, posted: d.posted, uploader: d.uploader, rating: d.rating,
      simpleLanguage: lang, pages: d.pages, mode: 0, time: Date.now()
    };
    await HistoryDao.put(info);
    await HistoryDao.trimTo(200);
  }

  /** 预览格初装（首块）；缩略图由格子 `onAppear` 经缓存按需取。 */
  private setPreviews(items: PreviewItem[]): void {
    const cells: PreviewCell[] = [];
    const seen: boolean[] = [];
    this.loadedPages.clear();
    this.maxLoadedPage = -1;
    for (let i = 0; i < items.length; i++) {
      if (seen[items[i].page]) {
        continue;
      }
      seen[items[i].page] = true;
      const cell: PreviewCell = new PreviewCell();
      cell.page = items[i].page;
      cell.url = items[i].imageUrl;
      cell.x = items[i].x;
      cell.y = items[i].y;
      cell.w = items[i].w;
      cell.h = items[i].h;
      cells.push(cell);
      this.loadedPages.add(items[i].page);
      if (items[i].page > this.maxLoadedPage) {
        this.maxLoadedPage = items[i].page;
      }
    }
    this.previewCells = cells;
    this.lastPrefRow = -1;
    this.chunkInflight.clear();
    this.chunkDone.clear();
    this.spriteClient = undefined;
    this.spriteCache.clear();
  }

  /**
   * 预览图 / 分块接口共用的客户端：新建 = 新 RCP session（`RcpHttpClient` 只建不关），
   * 所以不能按用户动作频率建（跳页滑杆松一次手就一次）。
   */
  private async ensurePreviewClient(): Promise<EhClient> {
    const existing: EhClient | undefined = this.spriteClient;
    if (existing !== undefined && this.spriteGid === this.gid) {
      return existing;
    }
    const site: EhSite = this.settings.site;
    const cookies: CookieStore = new CookieStore();
    await cookies.init(this.context());
    const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
    this.spriteClient = client;
    this.spriteReferer = EhUrl.referer(site);
    this.spriteGid = this.gid;
    return client;
  }

  /** 格子取图（成品裁剪缓存；切画廊过期返回空）。 */
  private spriteFor(cell: PreviewCell, gid: number): Promise<image.PixelMap | null> {
    return (async (): Promise<image.PixelMap | null> => {
      const key: string =
        PreviewSpriteCache.keyOf(cell.url, cell.x, cell.y, cell.w, cell.h);
      try {
        const client: EhClient = await this.ensurePreviewClient();
        const pm: image.PixelMap = await this.spriteCache.acquire(this.context(),
          client, this.spriteReferer, cell.url, cell.x, cell.y, cell.w, cell.h);
        if (this.gid !== gid) {
          PreviewSpriteCache.release(key);
          return null;
        }
        return pm;
      } catch (e) {
        Logger.error('Detail', `preview sprite failed gid=${gid} page=${cell.page}: ${e}`);
        return null;
      }
    })();
  }

  /** 可视窗缺页补块（chunk 可直取，不必顺序爬；行→页用稠密映射——未载行无格子，只能估算，偏了由 chunkDone 兜底只浪费一次）。 */
  private ensureVisibleChunks(firstRow: number, lastRow: number): void {
    if (this.data === null || this.pages <= 0) {
      return;
    }
    const chunks: number[] = [];
    for (let row = firstRow; row <= lastRow; row++) {
      for (let k = 0; k < 3; k++) {
        const page: number = row * 3 + k;
        if (page < 0 || page >= this.pages || this.loadedPages.has(page)) {
          continue;
        }
        const chunk: number = Math.floor(page / 20);
        if (!this.chunkInflight.has(chunk) && !this.chunkDone.has(chunk) && chunks.indexOf(chunk) < 0) {
          chunks.push(chunk);
        }
      }
    }
    for (let i = 0; i < chunks.length; i++) {
      this.ensureChunk(chunks[i]);
    }
  }

  /** 滚动预取：由预览区全局位置估算可视行，只取可视窗所在块（fling 直达可跳过中间块）。 */
  private prefetchByOffset(): void {
    const rows: number = Math.ceil(this.previewCells.length / 3);
    if (rows <= 0 || this.gridHeight <= 0 || this.gridTopY >= 0) {
      return;
    }
    const avgRowH: number = this.gridHeight / rows;
    if (avgRowH <= 0) {
      return;
    }
    const visibleRow: number = Math.floor(-this.gridTopY / avgRowH);
    if (visibleRow === this.lastPrefRow) {
      return;
    }
    this.lastPrefRow = visibleRow;
    this.ensureVisibleChunks(Math.max(0, visibleRow - 4), visibleRow + 6);
  }

  /** 滚到底追加下一块：只从已载前沿往前取（可见相邻），不回头补跳过的远端缺块（远端由可见窗按需取）。 */
  private appendNextChunk(): void {
    if (this.data === null || this.pages <= 0 || this.maxLoadedPage < 0) {
      return;
    }
    const next: number = this.maxLoadedPage + 1;
    if (next < this.pages) {
      this.ensureChunk(Math.floor(next / 20));
    }
  }

  /** 取单块并合并（按 `page` 去重；在飞/取空跳过）。 */
  private ensureChunk(chunk: number): void {
    if (this.data === null || this.chunkInflight.has(chunk) || this.chunkDone.has(chunk)) {
      return;
    }
    const d: GalleryDetail = this.data;
    const gid: number = this.gid;
    this.chunkInflight.add(chunk);
    this.fetchChunk(d, gid, chunk).catch((e: object) => {
      Logger.error('Detail', `preview chunk failed gid=${gid} chunk=${chunk}: ${e}`);
      if (this.gid === gid) {
        this.chunkInflight.delete(chunk);
      }
    });
  }

  private async fetchChunk(d: GalleryDetail, gid: number, chunk: number): Promise<void> {
    const site: EhSite = this.settings.site;
    const cookies: CookieStore = new CookieStore();
    await cookies.init(this.context());
    const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
    const fetched: PreviewItem[] =
      await client.getPreviews(site, d.gid, d.token, chunk);
    if (this.gid !== gid) {
      return;
    }
    this.chunkInflight.delete(chunk);
    const fresh: PreviewCell[] = [];
    for (let i = 0; i < fetched.length; i++) {
      if (!this.loadedPages.has(fetched[i].page)) {
        const cell: PreviewCell = new PreviewCell();
        cell.page = fetched[i].page;
        cell.url = fetched[i].imageUrl;
        cell.x = fetched[i].x;
        cell.y = fetched[i].y;
        cell.w = fetched[i].w;
        cell.h = fetched[i].h;
        fresh.push(cell);
        this.loadedPages.add(fetched[i].page);
        if (fetched[i].page > this.maxLoadedPage) {
          this.maxLoadedPage = fetched[i].page;
        }
      }
    }
    if (fresh.length > 0) {
      this.previewCells = this.previewCells.concat(fresh);
    } else {
      this.chunkDone.add(chunk);
    }
  }

  /**
   * 跳页半模态的邻域缩略图：只取 `page ± span` 覆盖到的 1–2 个分块。
   *
   * 分块接口是 `?p=<页/20>`（每块 20 张），所以「看 200 页前后」= 2 个请求，
   * 和「给整个画廊铺缩略图」（2000 页 = 100 个请求）不是一个量级。
   * 两块并行取（串行会把首屏等待翻倍）；全部失败才抛错，让半模态显示失败而不是「这里没有预览图」。
   */
  private async fetchJumpWindow(page: number, span: number): Promise<PreviewCell[]> {
    const d: GalleryDetail | null = this.data;
    if (d === null || this.pages <= 0) {
      return [];
    }
    const from: number = Math.max(0, page - span);
    const to: number = Math.min(this.pages - 1, page + span);
    const chunks: number[] = [];
    const first: number = Math.floor(from / 20);
    const last: number = Math.floor(to / 20);
    for (let chunk = first; chunk <= last; chunk++) {
      chunks.push(chunk);
    }
    const client: EhClient = await this.ensurePreviewClient();
    let failed: number = 0;
    const parts: PreviewItem[][] = await Promise.all(
      chunks.map((chunk: number): Promise<PreviewItem[]> =>
        client.getPreviews(this.settings.site, d.gid, d.token, chunk)
          .catch((e: object): PreviewItem[] => {
            failed += 1;
            Logger.error('Detail', `jump chunk failed gid=${d.gid} chunk=${chunk}: ${e}`);
            const none: PreviewItem[] = [];
            return none;
          })));
    const cells: PreviewCell[] = [];
    const seen: Set<number> = new Set<number>();
    for (let p = 0; p < parts.length; p++) {
      const items: PreviewItem[] = parts[p];
      for (let i = 0; i < items.length; i++) {
        const item: PreviewItem = items[i];
        if (item.page < from || item.page > to || seen.has(item.page)) {
          continue;
        }
        seen.add(item.page);
        const cell: PreviewCell = new PreviewCell();
        cell.page = item.page;
        cell.url = item.imageUrl;
        cell.x = item.x;
        cell.y = item.y;
        cell.w = item.w;
        cell.h = item.h;
        cells.push(cell);
      }
    }
    if (cells.length === 0 && failed > 0) {
      throw new Error(`jump window unavailable (page=${page})`);
    }
    cells.sort((a: PreviewCell, b: PreviewCell) => a.page - b.page);
    return cells;
  }

  /** 打开跳页半模态（与收藏/下载共用一个 `bindSheet`，见 `sheetKind`）。 */
  private openJumpSheet(): void {
    if (this.data === null || this.pages <= 0) {
      promptAction.showToast({ message: '详情还在加载' });
      return;
    }
    this.sheetKind = 3;
    // `bindSheet` 的 options（这里 detents 跟着 sheetKind 走）按上一次构建取值，
    // 先让 kind 的重渲染落地，下一拍再打开，否则会沿用别的半模态的挡位。
    setTimeout(() => {
      this.showSheet = true;
    }, 0);
  }

  /** 底部动作条收放：向下滚（且已过标题区）收起，向上滚立刻回来。 */
  private refreshBar(y: number): void {
    const dy: number = y - this.lastScrollY;
    if (Math.abs(dy) < BAR_HIDE_DELTA) {
      return;
    }
    this.lastScrollY = y;
    if (dy > 0) {
      if (!this.barHidden && y > BAR_HIDE_AFTER) {
        this.barHidden = true;
      }
    } else if (this.barHidden) {
      this.barHidden = false;
    }
  }

  /**
   * 收藏直发云端（无"已收藏"开关语义：盲切开关会误移类；按钮恒"收藏"→选类→POST）。
   * 未登录（无 `ipb_member_id`）人话提示、不发请求。
   */
  /** 收藏分类半模态内容（官方 `bindSheet` 承载）。 */
  @Builder
  favCatSheet() {
    FavCatSheet({
      options: this.sheetOptions(),
      onPick: (cat: number) => {
        this.addToFav(cat);
      },
      onCancel: () => {
        this.showSheet = false;
      }
    })
  }

  private sheetOptions(): FavCatOption[] {
    const options: FavCatOption[] = [];
    for (let i = 0; i < 10; i++) {
      options.push({
        cat: i,
        name: i < this.favCats.length ? this.favCats[i] : `收藏夹${i}`,
        // `-1` = 元信息未就绪（不显示假计数）；拉取成功后显示真实计数（含 0）。
        count: i < this.favCounts.length ? this.favCounts[i] : -1
      });
    }
    return options;
  }

  /** 拉收藏夹元信息（真实类名 + 计数）；失败给一次人话提示，不静默显示 0。 */
  private async ensureFavMeta(): Promise<void> {
    if (this.favMetaLoaded) {
      return;
    }
    try {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      if (!cookies.has('ipb_member_id')) {
        promptAction.showToast({ message: '登录后查看收藏夹' });
        return;
      }
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      const meta = await client.getFavoritesMeta(this.settings.site);
      this.favCats = meta.cats;
      this.favCounts = meta.counts;
      this.favMetaLoaded = true;
    } catch (e) {
      Logger.error('Detail', `favorites meta failed: ${e}`);
      promptAction.showToast({ message: '收藏夹信息加载失败，请重试' });
    }
  }

  /** 分享画廊链接（详情标题栏）。 */
  /** 下载状态文案（半模态即时反馈；无记录为空）。 */
  @Computed get downloadStatus(): string {
    const item: DownloadItem | undefined = downloadManager.itemOf(this.gid);
    if (item === undefined) {
      return '';
    }
    return `${DownloadDao.stateLabel(item.state)} · ${item.donePages}/${item.pages} 页`;
  }

  /** 加入下载队列（同一本重复点会复用记录并续传）。 */
  private async startDownload(): Promise<void> {
    if (this.pages <= 0) {
      promptAction.showToast({ message: '页数还没读到，请稍后重试' });
      return;
    }
    this.dlBusy = true;
    try {
      await downloadManager.init(this.context());
      await downloadManager.start(this.gid, this.token, this.title, this.category, this.pages,
        this.dlQuality, this.thumb, this.thumbUrl);
      this.showSheet = false;
      promptAction.showToast({ message: '已开始下载' });
    } catch (e) {
      Logger.error('Detail', `start download failed gid=${this.gid}: ${e}`);
      promptAction.showToast({ message: '加入下载失败，请重试' });
    } finally {
      this.dlBusy = false;
    }
  }

  @Builder
  downloadSheet() {
    Column({ space: 12 }) {
      Text(`共 ${this.pages} 页`)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      // 配额行：独立组件异步取 `home.php`（账号额度显示数字，IP 额度只说明模式，失败不显示）。
      QuotaLine()
      if (this.downloadStatus.length > 0) {
        Text(this.downloadStatus)
          .fontSize(12)
          .fontColor($r('app.color.brand'))
          .width('100%')
      }
      Text('画质')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 8 }) {
        ChipV2({
          chipV2Options: new ChipV2Options({
            label: new ChipV2Label({
              text: '原图',
              activatedFontColor: ColorMetrics.resourceColor($r('app.color.chip_active_text'))
            }),
            size: ChipV2Size.SMALL,
            allowClose: false,
            activated: this.dlQuality === DownloadQuality.ORIGINAL,
            activatedBackgroundColor: ColorMetrics.resourceColor($r('app.color.chip_active_bg')),
            onClicked: () => {
              this.dlQuality = DownloadQuality.ORIGINAL;
            }
          })
        })
        ChipV2({
          chipV2Options: new ChipV2Options({
            label: new ChipV2Label({
              text: '站点尺寸',
              activatedFontColor: ColorMetrics.resourceColor($r('app.color.chip_active_text'))
            }),
            size: ChipV2Size.SMALL,
            allowClose: false,
            activated: this.dlQuality === DownloadQuality.SITE,
            activatedBackgroundColor: ColorMetrics.resourceColor($r('app.color.chip_active_bg')),
            onClicked: () => {
              this.dlQuality = DownloadQuality.SITE;
            }
          })
        })
      }
      .width('100%')
      if (this.dlQuality === DownloadQuality.ORIGINAL) {
        Text('原图按文件大小计费（约 10 hits/MB），更费图片配额。')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      Button(this.dlBusy ? '正在加入…' : '开始下载')
        .width('100%')
        .enabled(!this.dlBusy)
        .onClick(() => {
          this.startDownload();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }

  @Builder
  sheetContent() {
    Column() {
      if (this.sheetKind === 1) {
        this.favCatSheet()
      } else if (this.sheetKind === 3) {
        JumpSheet({
          pages: this.pages,
          initialPage: this.progressPage >= 0 ? this.progressPage : 0,
          fetchWindow: (page: number, span: number) => this.fetchJumpWindow(page, span),
          spriteOf: (cell: PreviewCell) => this.spriteFor(cell, this.gid),
          onPick: (page: number) => {
            // 退场动画走完再进阅读器（见 `pendingJumpPage`）。
            this.pendingJumpPage = page;
            this.showSheet = false;
          }
        })
      } else {
        this.downloadSheet()
      }
    }
    .width('100%')
  }

  private async shareGallery(): Promise<void> {
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
        content: EhUrl.galleryDetail(this.settings.site, this.gid, this.token),
        title: this.title
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const abilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await controller.show(abilityContext, { previewMode: systemShare.SharePreviewMode.DEFAULT });
    } catch (e) {
      Logger.error('Detail', `share failed: ${e}`);
      promptAction.showToast({ message: '分享失败，请重试' });
    }
  }

  /** 标题栏心形图标入口：详情未回来时先提示（避免点了无反应）。 */
  private openFavSheet(): void {
    if (this.data === null) {
      promptAction.showToast({ message: '详情还在加载' });
      return;
    }
    this.openFavSheetAfterMeta().catch((_e: object) => {
      // 错误已在 ensureFavMeta 内处理
    });
  }

  /**
   * 先拉收藏夹元信息再开半模态：`bindSheet` 的 builder 只在打开时构建一次，
   * 打开后再更新 `favCats` 不会重绘 → 必须先有真实名称/计数，不能先显示占位再刷。
   */
  private async openFavSheetAfterMeta(): Promise<void> {
    if (!this.favMetaLoaded) {
      await this.ensureFavMeta();
    }
    this.sheetKind = 1;
    this.showSheet = true;
  }

  private async addToFav(cat: number): Promise<void> {
    this.showSheet = false;
    if (this.data === null) {
      return;
    }
    const d: GalleryDetail = this.data;
    let catName: string = `收藏夹${cat}`;
    if (cat < this.favCats.length) {
      catName = this.favCats[cat];
    }
    try {
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      if (!cookies.has('ipb_member_id')) {
        promptAction.showToast({ message: '登录后才能收藏' });
        return;
      }
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      await client.addFavorite(site, d.gid, d.token, cat);
      // 即时改态：标题栏心形变实心 + 收藏夹名（计数由下次拉元信息刷新）。
      this.isFavorited = true;
      this.favoriteName = catName;
      this.favMetaLoaded = false;
      promptAction.showToast({ message: `已收藏到${catName}` });
    } catch (e) {
      Logger.error('Detail', `fav failed gid=${d.gid}: ${e}`);
      promptAction.showToast({ message: '收藏失败，请稍后重试' });
    }
  }

  private async submitRating(value: number): Promise<void> {
    if (this.data === null || this.ratingBusy) {
      return;
    }
    const d: GalleryDetail = this.data;
    if (d.apiUid < 0 || d.apiKey.length === 0) {
      this.message = '登录后才能评分';
      return;
    }
    this.ratingBusy = true;
    try {
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      const result: RateResult =
        await client.rateGallery(site, d.gid, d.token, value, d.apiUid, d.apiKey);
      this.rating = result.rating;
      this.ratingCount = result.count;
      this.myRating = value;
      this.message = '';
    } catch (e) {
      Logger.error('Detail', `rate failed gid=${d.gid}: ${e}`);
      this.message = '评分失败，请稍后重试';
    }
    this.ratingBusy = false;
  }

  /** 骨架条（官方流光占位，见 `ui/Skeleton.ets`）。 */
  @Builder
  skeletonBar(width: string, height: number) {
    SkeletonBlock({ w: width, h: height, corner: 6 })
  }

  /** 头部骨架（无列表快照时）：封面 + 标题/上传者/页数占位，尺寸与真实头部一致。 */
  @Builder
  headerSkeleton() {
    Row({ space: 12 }) {
      SkeletonBlock({ w: 120, h: 160, corner: 8 })
      Column({ space: 10 }) {
        this.skeletonBar('38%', 18)
        this.skeletonBar('92%', 20)
        this.skeletonBar('64%', 20)
        this.skeletonBar('46%', 14)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
  }

  /** 单张骨架卡：两行占位条，高度与真实卡片接近。 */
  @Builder
  skeletonCard(height: number) {
    Column({ space: 10 }) {
      this.skeletonBar('68%', 16)
      this.skeletonBar('42%', 16)
    }
    .width('100%')
    .height(height)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
  }

  /** 加载中：评分 / 标签 / 评论 / 预览四块先占位，详情回来后就地替换（首帧不跳位）。 */
  @Builder
  loadingSkeletons() {
    this.skeletonCard(64)
    this.skeletonCard(132)
    this.skeletonCard(96)
    Grid() {
      Repeat(SKELETON_PREVIEW_CELLS)
        .each((ri: RepeatItem<number>) => {
          GridItem() {
            SkeletonBlock({ w: '100%', h: '100%', corner: THUMB_RADIUS })
          }
        })
        .key((i: number) => `${i}`)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(8)
    .rowsGap(8)
    .height(184)
    .width('100%')
  }

  /** 详情加载失败：错误卡片 + 重试（骨架态停留时不能没有任何反馈）。 */
  @Builder
  loadError() {
    Column({ space: 12 }) {
      Text(this.message)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Button('重新加载')
        .fontSize(14)
        .onClick(() => {
          this.retryLoad();
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
  }

  /** 重试：清错误 → 重新拉详情（`data` 仍为空则回到骨架态）。 */
  private retryLoad(): void {
    this.message = '';
    this.load();
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          // 顶部避让：与 HDS 标题栏同高但放在滚动内容里（内容可钻到栏下，渐变模糊才有内容穿过）。
          Column().height(this.windowState.safeTop + TITLE_BAR_H)
          if (this.title.length === 0 && this.thumb.length === 0) {
            this.headerSkeleton()
          } else {
          Row({ space: 12 }) {
            // 封面容器：共享元素绑定处（与列表缩略图同 id；转场同步容器圆角）。
            Column() {
              if (this.thumb.length > 0) {
                Image(this.thumb)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
              }
            }
            .width(120)
            .height(160)
            .borderRadius(8)
            .clip(true)
            .backgroundColor($r('app.color.bg_primary'))
            .geometryTransition(galleryGeometryId(this.gid))
            .transition(TransitionEffect.OPACITY)
            Column({ space: 4 }) {
              Text(catLabel(this.category))
                .fontSize(11)
                .fontColor(Color.White)
                .backgroundColor(catColor(this.category))
                .borderRadius(4)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .alignSelf(ItemAlign.Start)
              Text(this.title.length > 0 ? this.title : `gid ${this.gid}`)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Row({ space: 8 }) {
                Text(this.uploader)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                  .onClick(() => {
                    if (this.uploader.length === 0) {
                      return;
                    }
                    const param: SearchParam = {
                      query: this.uploader,
                      title: `上传者 ${this.uploader}`,
                      kind: 'uploader'
                    };
                    this.pageStack?.pushPathByName('搜索', param);
                  })
                SymbolGlyph($r('sys.symbol.eye_slash'))
                  .fontSize(16)
                  .fontColor([$r('app.color.text_secondary')])
                  .width(TOUCH_MIN)
                  .height(TOUCH_MIN)
                  .padding(6)
                  .onClick(() => {
                    this.confirmBlock(`uploader:${this.uploader}`, this.uploader, '上传者');
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              if (this.pages > 0) {
                // 页数沿站点惯例写 `9P`（与阅读器底栏 `X / N` 的页码语汇一致，不占一行中文）。
                Text(`${this.pages}P`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.bg_secondary'))
          .borderRadius(CARD_RADIUS)
          }
          if (this.data === null) {
            // 骨架/错误 → 真实内容：官方透明度过渡，避免整块硬切（与筛选面板同一手感）。
            Column({ space: 10 }) {
              if (this.message.length > 0) {
                this.loadError()
              } else {
                this.loadingSkeletons()
              }
            }
            .width('100%')
            .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
          } else {
          Row({ space: 8 }) {
            // 单组星：显示「我的评分（未打分则平均分）」；程序化赋值回调值 == 显示值 → 忽略（不误打分）。
            Rating({ rating: this.displayRating, indicator: false })
              .stars(5)
              .stepSize(0.5)
              .onChange((value: number) => {
                if (shouldSubmitRating(this.displayRating, value)) {
                  this.submitRating(value);
                }
              })
              .enabled(!this.ratingBusy)
            Column({ space: 2 }) {
              Text(this.ratingBusy ? '提交中…' : (this.myRating > 0 ? `我的 ★${this.myRating}` : '点星评分'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              if (this.ratingCount > 0) {
                Text(`平均 ★${this.rating.toFixed(2)} · ${this.ratingCount} 票`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(12)
          .alignItems(VerticalAlign.Center)
          .backgroundColor($r('app.color.bg_secondary'))
          .borderRadius(CARD_RADIUS)
          // 标签卡：官方 ChipV2 芯片分组（点按搜索 / 长按菜单语义不变）。
          Column() {
            Repeat(this.tagGroups)
              .each((ri: RepeatItem<TagGroup>) => {
                Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                  Text(`${ri.item.namespace}:`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin(4)
                    .padding({ top: 4, bottom: 4 })
                  Repeat(ri.item.tags)
                    .each((ti: RepeatItem<string>) => {
                      TagChip({
                        ns: ri.item.namespace, tag: ti.item,
                        onSearch: (ns: string, tag: string) => {
                          this.openTagSearch(ns, tag);
                        },
                        onExcludeSearch: (ns: string, tag: string) => {
                          this.openTagExcludeSearch(ns, tag);
                        },
                        onCopy: (ns: string, tag: string) => {
                          this.copyTagText(tagQueryOf(ns, tag));
                        },
                        onBlock: (ns: string, tag: string) => {
                          const tagQuery: string = tagQueryOf(ns, tag);
                          this.confirmBlock(tagQuery, tagQuery, '标签');
                        }
                      })
                    })
                    .key((tag: string, index: number) => `${index}:${tag}`)
                }
                .width('100%')
              })
              .key((group: TagGroup) => group.namespace)
          }
          .width('100%')
          .padding(8)
          .backgroundColor($r('app.color.bg_secondary'))
          .borderRadius(CARD_RADIUS)
          // 官方分区标题（排版基准 + 读屏标题语义）。它自带 16vp 左右内缩，外层补 32vp 抵消，标题才能和卡片同一条左边线。
          Column() {
            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '评论' }) })
          }
          .width('calc(100% + 32vp)')
          if (this.comments.length === 0) {
            Text('暂无评论')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else {
            Repeat(this.comments.slice(0, 3))
              .each((ri: RepeatItem<GalleryComment>) => {
                Column({ space: 2 }) {
                  // 分数只染数字：整行染色会让长用户名也跟着变色，读起来反而更乱。
                  Text() {
                    Span(`${ri.item.user} · ${commentDateText(ri.item.time)}`)
                      .fontColor($r('app.color.text_secondary'))
                    Span(ri.item.score !== undefined ? ` · ${commentScoreText(ri.item.score)}` : '')
                      .fontColor(commentScoreColor(ri.item.score))
                  }
                  .fontSize(12)
                  .width('100%')
                  Text(ri.item.text)
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
              })
              .key((comment: GalleryComment) => `${comment.id}`)
          }
          Row() {
            Text(this.comments.length > 0
              ? `${this.comments.length} 条评论 · 查看全部` : '去评论')
              .fontSize(13)
              .fontColor($r('app.color.brand'))
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .onClick(() => {
            const param: DetailParam = { gid: this.gid, token: this.token };
            this.pageStack?.pushPathByName('评论', param);
          })
          // 阅读入口移到屏幕底部的动作条（滚动时收起/回来），内容区不再单占一张卡。
          Column() {
            SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '预览' }) })
          }
          .width('calc(100% + 32vp)')
          Grid() {
            Repeat(this.previewCells)
              .each((ri: RepeatItem<PreviewCell>) => {
                GridItem() {
                  PreviewCropCell({
                    page: ri.item.page, w: ri.item.w, h: ri.item.h,
                    cacheKey: PreviewSpriteCache.keyOf(ri.item.url, ri.item.x, ri.item.y, ri.item.w, ri.item.h),
                    load: () => this.spriteFor(ri.item, this.gid)
                  })
                  .width('100%')
                  .onClick(() => {
                    this.openReader(ri.item.page);
                  })
                }
              })
              .key((cell: PreviewCell) => `${cell.page}`)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .width('100%')
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const pos = newArea.globalPosition;
            if (pos === undefined || pos.y === undefined) {
              return;
            }
            this.gridTopY = Number.parseFloat(pos.y.toString());
            this.gridHeight = Number.parseFloat(newArea.height.toString());
            this.prefetchByOffset();
          })
          }
          if (this.data !== null && this.message.length > 0) {
            Text(this.message)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
        }
        .width('100%')
        // 底部留出动作条背板 + 离底边距 + 安全区：最后一行预览图不会被压住。
        .padding({
          left: PAGE_PADDING,
          right: PAGE_PADDING,
          top: PAGE_PADDING,
          bottom: PAGE_PADDING + ACTION_BAR_H + ACTION_BAR_MARGIN + this.windowState.safeBottom
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_primary'))
      .onScrollEdge((side: Edge) => {
        if (side === Edge.End) {
          this.appendNextChunk();
        }
      })
      .onDidScroll(() => {
        this.refreshBar(this.scroller.currentOffset().yOffset);
      })
      // 底部动作条：官方 `HdsActionBar`（背板 + 主按钮 + 跳页），主按钮用自定义 builder 承载页码。
      if (this.pages > 0) {
        Column() {
          HdsActionBar({
            primaryButtonBuilder: () => {
              this.readPill()
            },
            // 官方动作条要求自定义主按钮显式给宽（不支持百分比），按图标 + 数字位数算。
            primaryButtonBuilderWidth: LengthMetrics.vp(this.readPillWidth),
            endButtons: [new ActionBarButton({
              baseIcon: $r('sys.symbol.list_number'),
              accessibilityText: '跳页',
              id: 'detail-jump',
              onClick: () => {
                this.openJumpSheet();
              }
            })],
            actionBarStyle: new ActionBarStyle({
              height: LengthMetrics.vp(ACTION_BAR_H),
              // 背板默认带不透明组件底色 → 看上去是一整块白；清成透明让模糊透出来
              // （与首页悬浮 tab 胶囊同一观感；光感档位仍由系统材质策略决定）。
              backgroundColor: ColorMetrics.resourceColor(Color.Transparent),
              backgroundBlurStyle: BlurStyle.COMPONENT_ULTRA_THICK
            }),
            isExpand: true,
            blurStrategy: BlurStrategy.ADAPTIVE
          })
        }
        .width('100%')
        // 靠右：Column 的交叉轴对齐 + 右边距（与页面留白对齐）。
        // 组件自己会避让底部安全区，这里只加一点呼吸，别再叠 safeBottom（会把它顶高一截）。
        .alignItems(HorizontalAlign.End)
        .padding({ right: PAGE_PADDING, bottom: ACTION_BAR_MARGIN })
        // 向下滚收起、向上滚回来：只做位移和淡出，不改布局，列表不会跟着跳。
        .translate({ y: this.barHidden ? ACTION_BAR_H + ACTION_BAR_MARGIN + 12 : 0 })
        .opacity(this.barHidden ? 0 : 1)
        .animation({ duration: 200, curve: Curve.EaseInOut })
      }
      }
      .width('100%')
      .height('100%')
      // 收藏分类：官方半模态 + 系统材质（不再自绘遮罩浮层）。
      .bindSheet($$this.showSheet, this.sheetContent(), {
        title: { title: this.sheetKind === 1 ? '选择收藏夹' : (this.sheetKind === 3 ? '跳页' : '下载') },
        // 跳页按内容定高；收藏/下载保留中/大两档。
        detents: this.sheetKind === 3
          ? [JUMP_SHEET_H]
          : [SheetSize.MEDIUM, SheetSize.LARGE],
        // 官方半模态材质。低算力设备上材质会退化成纯色背景，这是平台行为，不是参数没调对。
        systemMaterial: SHEET_MATERIAL,
        onDisappear: () => {
          this.showSheet = false;
          // 跳页选中后在这里进阅读器：等半模态退场，别和页面转场抢同一帧。
          const page: number = this.pendingJumpPage;
          if (page >= 0) {
            this.pendingJumpPage = -1;
            this.openReader(page);
          }
        }
      })
    }
    .titleBar({
      // 官方「渐变模糊」：内容从标题栏下方穿过时边界柔和（与首页/搜索页同一档位）。
      avoidLayoutSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_H)
        },
        blurStrategy: BlurStrategy.ADAPTIVE,
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: { titleStyle: { mainTitleColor: $r('app.color.text_primary') } }
        },
        scrollEffectStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent }
        },
        // 与首页/我的/其它 push 页统一：标题栏按钮区吃 HDS 沉浸光感材质。
        systemMaterialEffect: HDS_MATERIAL
      },
      content: {
        title: { mainTitle: '详情' },
        // 收藏入口：心形反映真实收藏态（已收藏实心品牌色 / 未收藏描边次要色）。
        menu: {
          value: [{
            content: {
              icon: new SymbolGlyphModifier($r(this.isFavorited ? 'sys.symbol.heart_fill' : 'sys.symbol.heart'))
                .fontColor([this.isFavorited ? $r('app.color.brand') : $r('app.color.text_secondary')]),
              action: () => {
                this.openFavSheet();
              }
            }
          }, {
            content: {
              icon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line'))
                .fontColor([$r('app.color.text_secondary')]),
              action: () => {
                this.sheetKind = 2;
                this.showSheet = true;
              }
            }
          }, {
            content: {
              icon: new SymbolGlyphModifier($r('sys.symbol.share'))
                .fontColor([$r('app.color.text_secondary')]),
              action: () => {
                this.shareGallery();
              }
            }
          }]
        }
      }
    })
    .bindToScrollable([this.scroller])
    // 关闭系统默认转场：共享元素（geometryTransition + animateTo）才不会被滑入动画叠加。
    .systemTransition(NavigationSystemTransitionType.NONE)
    .onBackPressed(() => {
      this.popAnimated();
      return true;
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
      const param: DetailParam | undefined = ctx.pathInfo.param as DetailParam | undefined;
      if (param === undefined) {
        this.message = '缺少参数';
        return;
      }
      this.gid = param.gid;
      this.token = param.token;
      this.refreshProgress();
      // 列表快照先渲染（0 帧有标题/封面/页数），网络详情回来再覆盖并补 tags/评论/预览。
      const preview: DetailPreview | undefined = param.preview;
      if (preview !== undefined) {
        this.title = preview.title;
        this.category = preview.category;
        this.uploader = preview.uploader;
        this.rating = preview.rating;
        this.pages = preview.pages;
        this.thumb = preview.thumb;
        this.thumbUrl = preview.thumbUrl;
      }
      this.load();
    })
    // 从阅读器返回时进度会变，入口文案要跟着刷新。
    .onShown(() => {
      this.refreshProgress();
    })
  }
}
