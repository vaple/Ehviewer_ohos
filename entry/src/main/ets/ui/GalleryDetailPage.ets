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
import { PreviewGridCell } from './PreviewGridCell';
import { PreviewGridSource, PreviewRow } from './PreviewGridSource';
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
import { CARD_RADIUS, ACTION_BAR_BTN_H, ACTION_BAR_H, ACTION_BAR_MARGIN, HDS_MATERIAL, JUMP_SHEET_H, PAGE_PADDING, THUMB_RADIUS, TOUCH_MIN, commentScoreColor, sheetBackdrop } from './Materials';
import { commentDateText, commentScoreText } from '../common/CommentText';
import { galleryGeometryId } from './GalleryRow';
import { SkeletonBlock } from './Skeleton';
import { TITLE_BAR_H } from './NavStyle';
import { downloadManager } from '../service/DownloadManager';
import { DownloadItem, DownloadQuality, DownloadState } from '../model/DownloadRecord';
import { DownloadDao } from '../db/dao/DownloadDao';
import { QuotaLine } from './QuotaLine';
import { PreviewCell } from '../model/PreviewCell';
import { chunkOfPage } from '../common/JumpStrip';
import { shouldLoadAtSpeed, screensPerSecond, SPEED_SAMPLE_MS } from '../common/PreviewLoadPolicy';
import { JumpSheet } from './JumpSheet';
import { NsLabel, TagChip } from './TagChip';
import { TagDb } from '../tagdb/TagDb';

/** 预览网格列数（设计规范值：三列等宽，列/行间距 8vp）。 */
const GRID_COLUMNS: number = 3;
const GRID_GAP: number = 8;
/** 行内单格宽度：三列均分，扣掉两个列间距（`calc` 跟容器走，不按机型写死）。 */
const GRID_CELL_WIDTH: string = `calc((100% - ${(GRID_COLUMNS - 1) * GRID_GAP}vp) / ${GRID_COLUMNS})`;
/** 站点 `#gdt` 典型格子 200×137；详情首块没给几何时用它占位（宽/高）。 */
const DEFAULT_PREVIEW_ASPECT: number = 200 / 137;
/** 预取提前量（页）：可视窗尾部再往后取这么多页（= 一个站点块），跨块时不会空窗（一行 3 页）。 */
const PREFETCH_PAGES: number = 20;
/** 失败块冷却（ms）：取块失败后至少隔这么久才重试，防止一次抖动打成请求风暴。 */
const CHUNK_RETRY_MS: number = 3000;
/** 停稳后的静默窗（ms）：final 的 index 回调可能还在路上，安静下来再取块（与跳页条带同口径）。 */
const PREVIEW_SETTLE_MS: number = 120;

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
  /**
   * 预览网格（行 = 3 页）：总行数由 `pages` 决定，未取到的页先占位。
   * 为什么是独立数据源 + `List`：网格必须是列表里的普通行，**不能**再嵌一个同向可滚动组件
   * （`Grid` 会吃掉手势 → 页面停在首块 20 张，见 `ui/AGENTS.md` #69）。
   */
  private gridSource: PreviewGridSource = new PreviewGridSource(GRID_COLUMNS);
  /** 预览网格总页数：`pages` 与首块自带的最大页码取大（`Length` 解析失败时首块仍能显示）。 */
  private previewPages: number = 0;
  /** 占位宽高比（取自首块首格；骨架与未取到的格子共用，避免数据到达时行高跳动）。 */
  private placeholderAspect: number = DEFAULT_PREVIEW_ASPECT;
  /** 在飞分块（同块并发合并；失败摘掉，冷却后可重试）。 */
  private chunkInflight: Set<number> = new Set<number>();
  /** 失败块的冷却起点（ms）：取块失败后按 `CHUNK_RETRY_MS` 限流，避免一次网络抖动打成请求风暴。 */
  private chunkFailedAt: Map<number, number> = new Map<number, number>();
  /** 最近一次上报的可视行（速度采样 / 停稳取块都用它）。 */
  private visibleRowStart: number = -1;
  private visibleRowEnd: number = -1;
  /** 停稳取块的定时器（`-1` = 没有待触发的）。 */
  private settleTimer: number = -1;
  /** 视口高度（vp，`List.onAreaChange` 读；速度按「屏/秒」归一化要用）。 */
  private viewportH: number = 0;
  /** 速度采样窗起点（`0` = 下一拍重新取样；`onScrollStart` 重置）。 */
  private speedSampleAt: number = 0;
  private speedSampleOffset: number = 0;
  private spriteCache: PreviewSpriteCache = new PreviewSpriteCache();
  private spriteClient: EhClient | undefined = undefined;
  private spriteGid: number = -1;
  private spriteReferer: string = '';
  /** 块级缓存：详情网格与跳页条带共用，同一块不并发发两次；随 `setPreviews` 清空。 */
  private chunkCells: Map<number, PreviewCell[]> = new Map<number, PreviewCell[]>();
  private chunkPromises: Map<number, Promise<PreviewCell[]>> = new Map<number, Promise<PreviewCell[]>>();
  @Local comments: GalleryComment[] = [];
  @Local showSheet: boolean = false;
  /**
   * 半模态内容：1 = 收藏夹，2 = 下载，3 = 跳页，4 = 标签释义。
   * 同一次只能挂一个半模态（同一节点挂两个 `bindSheet` 会静默失效），所以用 kind 切内容，不要并列写多个。
   */
  @Local sheetKind: number = 0;
  /** 标签释义半模态的原文（`ns`/`tag` 都是站点原串；`showSheet = true` 之前必须先写好，见 `ui/AGENTS.md` #20）。 */
  @Local explainNs: string = '';
  @Local explainTag: string = '';
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
    .backgroundColor($r('sys.color.comp_background_emphasize'))
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

  aboutToDisappear(): void {
    // 离页后停稳定时器不应再发预览请求（此时页面状态已不可用）。
    this.cancelSettle();
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
      const rule: Filter = { id: 0, text: qualifyTag(term), enable: true };
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
      gid: d.gid, token: d.token, title: d.title, thumb: d.thumb,
      category: d.category, posted: d.posted, uploader: d.uploader, rating: d.rating,
      simpleLanguage: lang, pages: d.pages, time: Date.now()
    };
    await HistoryDao.put(info);
    await HistoryDao.trimTo(200);
  }

  /**
   * 预览网格初装：按总页数铺满占位行，再把详情自带的首块（20 页）写进去。
   * 其余块由速度采样（慢拖/慢惯性）与停稳兜底按块取，不再靠滚到列表底部的边事件。
   */
  private setPreviews(items: PreviewItem[]): void {
    const cells: PreviewCell[] = [];
    const seen: Set<number> = new Set<number>();
    let lastPage: number = -1;
    for (let i = 0; i < items.length; i++) {
      if (seen.has(items[i].page)) {
        continue;
      }
      seen.add(items[i].page);
      const cell: PreviewCell = new PreviewCell();
      cell.page = items[i].page;
      cell.url = items[i].imageUrl;
      cell.x = items[i].x;
      cell.y = items[i].y;
      cell.w = items[i].w;
      cell.h = items[i].h;
      cells.push(cell);
      if (items[i].page > lastPage) {
        lastPage = items[i].page;
      }
    }
    this.chunkInflight.clear();
    this.chunkFailedAt.clear();
    this.chunkCells.clear();
    this.chunkPromises.clear();
    // 行数按「站点页数」与「首块自带的最大页码」的较大者：`Length:` 解析不出来时预览也不该整块空白。
    this.previewPages = Math.max(this.pages, lastPage + 1);
    this.placeholderAspect = cells.length > 0 && cells[0].h > 0
      ? cells[0].w / cells[0].h : DEFAULT_PREVIEW_ASPECT;
    this.gridSource.reset(this.previewPages);
    this.gridSource.apply(cells);
    // 详情自带的预览就是第 0 块：先塞进块缓存，跳页条带默认从第 1 页打开时不再重下一遍。
    // 复用同一批 `PreviewCell` 实例是安全的：两条路径都只读它（条带写入时是拷贝到自己的格子里）。
    this.chunkCells.set(0, cells);
    this.spriteClient = undefined;
    this.spriteCache.clear();
    // 首屏不先给一片灰：详情一回来就按当前可视行取一次（此时通常只命中首块）。
    this.scheduleSettle();
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

  /**
   * 速度采样：每 `SPEED_SAMPLE_MS` 算一次「屏/秒」，只有不快于门限时才取块。
   *
   * 为什么判据是「屏/秒」：一行在视口里的停留时长 `T = 1 / (屏/秒)`，与屏高、行高都无关；
   * 同一个「行/秒」在 9 行屏和 18 行折叠屏上，用户感知的速度差一倍
   * （见 `common/PreviewLoadPolicy`）。所以快甩自动不取、慢拖与慢惯性自动取，
   * 不需要再单独判 `ScrollState.Fling`（慢 fling 的行确实停留够久，该取）。
   */
  private sampleSpeed(offsetVp: number): void {
    const now: number = Date.now();
    if (this.speedSampleAt === 0) {
      this.speedSampleAt = now;
      this.speedSampleOffset = offsetVp;
      return;
    }
    const dt: number = now - this.speedSampleAt;
    if (dt < SPEED_SAMPLE_MS) {
      return;
    }
    const dy: number = offsetVp - this.speedSampleOffset;
    this.speedSampleAt = now;
    this.speedSampleOffset = offsetVp;
    if (this.viewportH <= 0) {
      return;
    }
    if (!shouldLoadAtSpeed(screensPerSecond(dy, this.viewportH, dt))) {
      return;
    }
    this.requestRows(this.visibleRowStart, this.visibleRowEnd + 1);
  }

  /** 取消待触发的停稳取块（新一轮滑动开始 / 换画廊 / 离开页面）。 */
  private cancelSettle(): void {
    if (this.settleTimer >= 0) {
      clearTimeout(this.settleTimer);
      this.settleTimer = -1;
    }
  }

  /**
   * 停稳兜底：速度门限已经处理「慢拖 / 慢惯性」，这里保证「抬手即停」也有一次最终测量，
   * 同时兜住失败块的重试（冷却已过的块才会重发）。
   */
  private scheduleSettle(): void {
    this.cancelSettle();
    this.settleTimer = setTimeout(() => {
      this.settleTimer = -1;
      this.requestRows(this.visibleRowStart, this.visibleRowEnd + 1);
    }, PREVIEW_SETTLE_MS);
  }

  /**
   * 取这些预览行覆盖的块（尾部再往后多取 `PREFETCH_PAGES` 页 ≈ 一个站点块，跨块不空窗）。
   * 行→块用 `chunkOfPage`：甩动/跳页直达时中间没看过的块不该发请求；同块并发由 `previewChunk` 合并。
   * 调用点只有速度采样与停稳兜底，滑动过程中的每一帧都不会发请求。
   */
  private requestRows(firstRow: number, lastRow: number): void {
    if (this.data === null || this.previewPages <= 0) {
      return;
    }
    const rows: number = this.gridSource.totalCount();
    if (rows <= 0) {
      return;
    }
    const columns: number = this.gridSource.columns;
    const from: number = Math.max(0, Math.min(firstRow, lastRow));
    const to: number = Math.min(rows - 1, Math.max(firstRow, lastRow));
    const firstPage: number = from * columns;
    const lastPage: number = Math.min((to + 1) * columns - 1 + PREFETCH_PAGES, this.previewPages - 1);
    for (let chunk = chunkOfPage(firstPage); chunk <= chunkOfPage(lastPage); chunk++) {
      this.ensureChunk(chunk);
    }
  }

  /** 取单块：已取到 / 在飞 / 失败冷却中直接跳过。 */
  private ensureChunk(chunk: number): void {
    if (this.data === null || chunk < 0) {
      return;
    }
    if (this.chunkInflight.has(chunk) || this.chunkCells.has(chunk)) {
      return;
    }
    const failedAt: number | undefined = this.chunkFailedAt.get(chunk);
    if (failedAt !== undefined && Date.now() - failedAt < CHUNK_RETRY_MS) {
      return;
    }
    const gid: number = this.gid;
    this.chunkInflight.add(chunk);
    this.fetchChunk(gid, chunk).catch((e: object) => {
      Logger.error('Detail', `preview chunk failed gid=${gid} chunk=${chunk}: ${e}`);
      if (this.gid === gid) {
        this.chunkInflight.delete(chunk);
        this.chunkFailedAt.set(chunk, Date.now());
      }
    });
  }

  /**
   * 取一块（20 页）的预览格。请求本身失败要抛：调用方要能区分「这块确实没有预览」与「这次没取到」。
   */
  private async fetchChunkCells(chunk: number): Promise<PreviewCell[]> {
    const d: GalleryDetail | null = this.data;
    if (d === null) {
      throw new Error('detail not ready');
    }
    const gid: number = this.gid;
    const client: EhClient = await this.ensurePreviewClient();
    const items: PreviewItem[] = await client.getPreviews(this.settings.site, d.gid, d.token, chunk);
    if (this.gid !== gid) {
      // 中途换了画廊：不能把这份结果当成「没有预览」落进缓存 / done。
      throw new Error('gallery changed');
    }
    const cells: PreviewCell[] = [];
    for (let i = 0; i < items.length; i++) {
      const cell: PreviewCell = new PreviewCell();
      cell.page = items[i].page;
      cell.url = items[i].imageUrl;
      cell.x = items[i].x;
      cell.y = items[i].y;
      cell.w = items[i].w;
      cell.h = items[i].h;
      cells.push(cell);
    }
    return cells;
  }

  /** 网格与跳页条带共用的块入口：先命中缓存，再复用同块的 in-flight promise（同一块不发两次）。 */
  private previewChunk(chunk: number): Promise<PreviewCell[]> {
    const cached: PreviewCell[] | undefined = this.chunkCells.get(chunk);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const running: Promise<PreviewCell[]> | undefined = this.chunkPromises.get(chunk);
    if (running !== undefined) {
      return running;
    }
    const gid: number = this.gid;
    const p: Promise<PreviewCell[]> = this.fetchChunkCells(chunk);
    this.chunkPromises.set(chunk, p);
    p.then((cells: PreviewCell[]) => {
      // 只清理自己那一条：切画廊清空后可能有新请求占了同一个 key，别把新的删掉。
      if (this.chunkPromises.get(chunk) === p) {
        this.chunkPromises.delete(chunk);
      }
      if (this.gid === gid) {
        this.chunkCells.set(chunk, cells);
      }
    }).catch((_e: object) => {
      if (this.chunkPromises.get(chunk) === p) {
        this.chunkPromises.delete(chunk);
      }
    });
    return p;
  }

  private async fetchChunk(gid: number, chunk: number): Promise<void> {
    const fetched: PreviewCell[] = await this.previewChunk(chunk);
    if (this.gid !== gid) {
      return;
    }
    this.chunkInflight.delete(chunk);
    this.chunkFailedAt.delete(chunk);
    if (fetched.length > 0) {
      this.gridSource.apply(fetched);
    }
    // 空数组 = 这块确实没有预览（请求本身成功）：`previewChunk` 已把它写进块缓存，`ensureChunk` 不会再打。
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

  /** 打开标签释义半模态（同样复用那一个 `bindSheet` 与 `sheetKind`）。 */
  private openExplainSheet(ns: string, tag: string): void {
    // 内容在 builder 构建时才读：先把原串落地，再打开（`ui/AGENTS.md` #20）。
    this.explainNs = ns;
    this.explainTag = tag;
    this.sheetKind = 4;
    // 与跳页同理：`detents`/标题按上一次构建取值，先让 kind 的重渲染落地，下一拍再打开。
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

  /** 标签释义半模态内容：中文名（主）/ 原文 `ns:tag`（次）/ 释义正文（长文可滚动）。 */
  @Builder
  explainSheet() {
    Column({ space: 8 }) {
      Text(TagDb.translateTag(this.explainNs, this.explainTag))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(`${this.explainNs}:${this.explainTag}`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      // 释义最长有整篇 wiki 段落（上游换行已还原），必须能滚，交给半模态的中/大两档高度。
      Scroll() {
        Text(TagDb.intro(this.explainNs, this.explainTag))
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      // 内容比视口矮时不要垂直居中：释义必须从第一行贴顶（同 `TagSuggestionPanel`）。
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
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
          .fontColor($r('sys.color.brand'))
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
              text: '原图'
            }),
            size: ChipV2Size.SMALL,
            allowClose: false,
            activated: this.dlQuality === DownloadQuality.ORIGINAL,
            onClicked: () => {
              this.dlQuality = DownloadQuality.ORIGINAL;
            }
          })
        })
        ChipV2({
          chipV2Options: new ChipV2Options({
            label: new ChipV2Label({
              text: '站点尺寸'
            }),
            size: ChipV2Size.SMALL,
            allowClose: false,
            activated: this.dlQuality === DownloadQuality.SITE,
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
          loadChunk: (chunk: number) => this.previewChunk(chunk),
          spriteOf: (cell: PreviewCell) => this.spriteFor(cell, this.gid),
          onPick: (page: number) => {
            // 退场动画走完再进阅读器（见 `pendingJumpPage`）。
            this.pendingJumpPage = page;
            this.showSheet = false;
          }
        })
      } else if (this.sheetKind === 4) {
        this.explainSheet()
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

  /** 骨架预览格：与真图同列宽、同占位比例（行高一致，详情回来时不跳位）。 */
  @Builder
  skeletonPreviewCell() {
    Column() {
      SkeletonBlock({ h: '100%', corner: THUMB_RADIUS })
    }
    .width(GRID_CELL_WIDTH)
    .aspectRatio(this.placeholderAspect)
  }

  /** 骨架预览行（官方流光占位，不是内容遮罩）。 */
  @Builder
  skeletonPreviewRow() {
    Row({ space: GRID_GAP }) {
      this.skeletonPreviewCell()
      this.skeletonPreviewCell()
      this.skeletonPreviewCell()
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 加载中：评分 / 标签 / 评论 / 预览四块先占位，详情回来后就地替换（首帧不跳位）。 */
  @Builder
  loadingSkeletons() {
    this.skeletonCard(64)
    this.skeletonCard(132)
    this.skeletonCard(96)
    Column({ space: GRID_GAP }) {
      this.skeletonPreviewRow()
      this.skeletonPreviewRow()
    }
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

  /**
   * 一行预览（3 格等宽）。格子自己从「页码占位」切成真图；取块由停稳事件驱动，不在滑动中发请求。
   * 行数固定（`gridSource`），所以滚动范围稳定，未取到的页只是灰格，不会把列表越滚越长。
   */
  @Builder
  previewRow(row: PreviewRow) {
    Row({ space: GRID_GAP }) {
      Repeat(row.cells)
        .each((ri: RepeatItem<PreviewCell>) => {
          Column() {
            PreviewGridCell({
              cell: ri.item,
              aspect: this.placeholderAspect,
              spriteOf: (cell: PreviewCell) => this.spriteFor(cell, this.gid)
            })
          }
          .width(GRID_CELL_WIDTH)
          .onClick(() => {
            this.openReader(ri.item.page);
          })
        })
        .key((cell: PreviewCell) => `${cell.page}`)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
  }

  /** 重试：清错误 → 重新拉详情（`data` 仍为空则回到骨架态）。 */
  private retryLoad(): void {
    this.message = '';
    this.load();
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
      List({ space: GRID_GAP, scroller: this.scroller }) {
        // 头部（封面 / 评分 / 标签 / 评论 / 「预览」标题）作为一个 ListItem：
        // 预览网格必须是列表自己的行，不能再嵌同向可滚动组件（见 `gridSource` 注释）。
        ListItem() {
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
                    // 上传者不再是一种搜索模式：它就是一条 `uploader:"…"` 条件，进搜索页后是普通 chip。
                    const param: SearchParam = {
                      query: `uploader:"${this.uploader}"`,
                      kind: 'keyword'
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
          // 页面级提示（评分失败 / 登录后才能评分）：跟在评分卡下面，用户点完就在眼前。
          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          // 标签卡：官方 ChipV2 芯片分组（点按搜索 / 长按菜单语义不变）。
          Column() {
            Repeat(this.tagGroups)
              .each((ri: RepeatItem<TagGroup>) => {
                Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                  NsLabel({ ns: ri.item.namespace })
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
                        },
                        onExplain: (ns: string, tag: string) => {
                          this.openExplainSheet(ns, tag);
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
              .fontColor($r('sys.color.brand'))
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
          }
        }
        .width('100%')
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: PAGE_PADDING })
        }
        LazyForEach(this.gridSource, (row: PreviewRow) => {
          ListItem() {
            this.previewRow(row)
          }
        }, (row: PreviewRow, index: number) => `${this.gridSource.generation}:${index}`)
        // 尾项：底部安全区（动作条背板不会压住最后一行预览）。
        ListItem() {
          Column()
            .width('100%')
            .padding({
              left: PAGE_PADDING,
              right: PAGE_PADDING,
              bottom: PAGE_PADDING + ACTION_BAR_H + ACTION_BAR_MARGIN + this.windowState.safeBottom
            })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_primary'))
      .cachedCount(4)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        // 视口高度（vp）：速度按「屏/秒」归一化用，旋转/折叠展开后自动跟随。
        this.viewportH = Number.parseFloat(newArea.height.toString());
      })
      .onScrollIndex((start: number, end: number) => {
        // List 第 0 项是头部、最后一项是尾项 → 预览行索引 = item 索引 - 1。
        // 这里只记可视窗：是否取块由 `sampleSpeed`（屏/秒）与停稳兜底决定。
        this.visibleRowStart = start - 1;
        this.visibleRowEnd = end - 1;
      })
      .onScrollStart(() => {
        // 新手势开始：上一轮还没触发的停稳取块作废；速度从这一拍重新取样。
        this.cancelSettle();
        this.speedSampleAt = 0;
      })
      .onScrollStop(() => {
        this.scheduleSettle();
      })
      .onDidScroll(() => {
        const y: number = this.scroller.currentOffset().yOffset;
        this.refreshBar(y);
        this.sampleSpeed(y);
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
        title: { title: this.sheetKind === 1 ? '选择收藏夹' : (this.sheetKind === 3 ? '跳页' : (this.sheetKind === 4 ? '标签释义' : '下载')) },
        // 跳页按内容定高；收藏 / 下载 / 释义都用中/大两档（释义正文长，靠大档 + 内部滚动）。
        detents: this.sheetKind === 3
          ? [JUMP_SHEET_H]
          : [SheetSize.MEDIUM, SheetSize.LARGE],
        // 半模态材质必须组件级设置（应用级开关不覆盖 `bindSheet`，见 `Materials.ets`）。
        backgroundColor: sheetBackdrop().backgroundColor,
        systemMaterial: sheetBackdrop().material,
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
                .fontColor([this.isFavorited ? $r('sys.color.brand') : $r('app.color.text_secondary')]),
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
