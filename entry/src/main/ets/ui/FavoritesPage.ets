import { common } from '@kit.AbilityKit';
import { AppStorageV2, ColorMetrics, LengthMetrics, PersistenceV2, SymbolGlyphModifier, promptAction } from '@kit.ArkUI';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient, FavPage } from '../network/EhClient';
import { DetailParam } from '../model/DetailParam';
import { Logger } from '../common/Logger';
import { hapticTap } from '../common/Haptic';
import { isAllSelected, submittedKeyword, toggleGid } from '../common/FavList';
import { errorText } from '../common/ErrorText';
import { AppSettings } from '../state/AppSettings';
import { WindowState } from '../state/WindowState';
import {
  ActionBarButton, ActionBarStyle, BlurStrategy, HdsActionBar, HdsNavDestination, HdsNavigationMenuContentOptions
} from '@kit.UIDesignKit';
import { PagedDataSource, PREFETCH_TAIL, shouldFetchMore } from '../common/PagedList';
import { GalleryListFeed } from './GalleryListFeed';
import { GalleryListPage } from '../parser/GalleryListParser';
import { GalleryRow, GalleryRowItem, pushGalleryDetail, toDetailPreview } from './GalleryRow';
import { GalleryRowSkeleton, SKELETON_ROW_INDICES } from './GalleryRowSkeleton';
import { ImageStore } from '../service/ImageStore';
import { catLabel } from './CategoryStyle';
import { FavCatSheet, FavCatOption } from './FavCatSheet';
import { CARD_GAP, PAGE_PADDING, TOUCH_MIN, sheetBackdrop } from './Materials';
import { navTitleBarStyle, TITLE_BAR_H } from './NavStyle';
import { RefreshSpinner } from './RefreshSpinner';

/**
 * 云收藏（源 `FavoritesScene` 子集）：类 tabs（含计数）+ 收藏内搜索 + 排序切换 + 行移动/删除。
 * 单向同步：以服务端为准，本地库不再引用（存量旧数据直接丢弃）。
 * 未登录人话提示、不发请求。
 *
 * 版式与列表页一致（`GalleryRow`），多选走系统的「长按进入」惯例：
 * 长按任一行 → 行尾出圆形勾选、标题栏换成「已选 N 项 + 删除/移动」、底部 `HdsActionBar` 承载批量动作。
 * 不用 HDS 的 `hdsListItemCard`：它的 `TextOptions` 没有 maxLines（标题只能全文换行，
 * 行高会从 202px 涨到 427px），见 `ui/AGENTS.md` #76。
 */
@ComponentV2
export struct FavoritesPage {
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  @Local favCat: number = -1;
  @Local keyword: string = '';
  /** 输入框草稿：与 `keyword`（已生效的搜索词）分开，避免边输入边搜。 */
  @Local draft: string = '';
  @Local order: string = 'p';
  @Local cats: string[] = [];
  @Local counts: number[] = [];
  @Local items: GalleryRowItem[] = [];
  @Local message: string = '加载中…';
  /** 首屏加载（首帧还没有任何条目时用它画骨架）。 */
  @Local firstLoad: boolean = true;
  /** 下拉刷新中（`Refresh` 双向绑定）。 */
  @Local isRefreshing: boolean = false;
  /** 当前下拉距离（vp，来自 `Refresh.onOffsetChange`），只用于刷新圈的淡入。 */
  @Local pullOffset: number = 0;
  /**
   * 列表内容正在**整体重建**（首屏 / 切分类 / 切排序 / 提交搜索）→ 画骨架行。
   *
   * 为什么不复用 `isLoading`：它是普通字段，改它不触发重绘，UI 分支会停在旧值。
   * 也不复用 `isRefreshing`：下拉刷新要**保留旧列表**（只叠一个圈），不能换成骨架。
   */
  @Local reloading: boolean = false;
  /** 正在取**下一页**（滚到底触发）→ 列表底部一行「加载中…」，不动已有内容。 */
  @Local loadingMore: boolean = false;
  /** 待移动画廊 gid（`-1` = 未开类选择器）。 */
  @Local moveGid: number = -1;
  /** 多选态（选中 gid 集合，不落盘；退出多选即清空）。 */
  @Local selectedGids: number[] = [];
  /** 多选模式开关（批量移动到 0–9 / 删除走底部动作条）。 */
  @Local selectMode: boolean = false;
  /** 批量移动：类选择器为批量服务（`moveGid` 单条逻辑不动）。 */
  @Local batchMove: boolean = false;
  private moveToken: string = '';
  /** 系统安全区（顶部避让 = safeTop + 标题栏高）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  /** 收藏列表滚动器（标题栏渐变模糊用）。 */
  private scroller: Scroller = new Scroller();
  /** 搜索框控制器（官方收键盘手段：`SearchController.stopEditing()`）。 */
  private searchController: SearchController = new SearchController();
  private isLoading: boolean = false;
  /**
   * 缩略图取图用的客户端与引用站点（`load()` 里跟着登录态一起建）。
   * 单独存一份的理由：行是在**可见时**才取图的（`onAppear`），那时 `load()` 的局部变量早就出栈了。
   */
  private thumbClient: EhClient | null = null;
  private thumbSite: EhSite = EhSite.E;
  private thumbStore: ImageStore | null = null;
  /** 同一张缩略图的在飞请求（按 gid 去重；`ImageStore` 自己也按 URL 合并，这里只是省一次 await）。 */
  private thumbInflight: Map<number, Promise<string>> = new Map<number, Promise<string>>();
  /** 分页状态唯一持有者；每取一页顺手刷新收藏分类/计数/排序元信息。 */
  private feed: GalleryListFeed = new GalleryListFeed(async (url: string): Promise<GalleryListPage> => {
    const cookies: CookieStore = new CookieStore();
    await cookies.init(this.context());
    const client: EhClient = this.clientOf(cookies);
    const fav: FavPage = await client.getFavoritesPage(url, this.settings.site, this.settings.thumbSize);
    this.cats = fav.cats;
    this.counts = fav.counts;
    if (fav.order.length > 0) {
      this.order = fav.order;
    }
    return { items: fav.items, next: fav.next };
  });
  /** 懒加载数据源（只负责 items + hasMore；预取由页面在滚动到底时显式触发）。 */
  private dataSource: PagedDataSource<GalleryRowItem> =
    new PagedDataSource<GalleryRowItem>(() => {
      return this.isLoading;
    });
  private pageStack: NavPathStack | undefined = undefined;

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private clientOf(cookies: CookieStore): EhClient {
    return new EhClient(new RcpHttpClient(), cookies);
  }

  /**
   * 取一行缩略图（行可见时触发）。空串 = 该条目站点没给缩略图 / 还没登录。
   * 失败直接抛给调用方：那个位置会显示可点的重试图标（不再像 `loadMissingThumbs` 那样静默吞掉）。
   */
  private ensureThumb(item: GalleryRowItem): void {
    if (item.thumb.length > 0 || item.thumbUrl.length === 0) {
      return;
    }
    if (this.thumbInflight.has(item.gid)) {
      return;
    }
    const task: Promise<string> = this.fetchThumb(item);
    this.thumbInflight.set(item.gid, task);
    task.then((uri: string) => {
      this.thumbInflight.delete(item.gid);
      if (uri.length > 0) {
        // `thumb` 是 `@Trace`：写进去这一行自己就切成真图。
        item.thumb = uri;
      }
    }).catch((e: object) => {
      this.thumbInflight.delete(item.gid);
      // 失败保留骨架（下次可见/下次进入会重试）；记日志但不打扰用户。
      Logger.error('Fav', `thumb load failed gid=${item.gid}: ${e}`);
    });
  }

  private async fetchThumb(item: GalleryRowItem): Promise<string> {
    const client: EhClient | null = this.thumbClient;
    if (client === null) {
      // 还没登录/还没拿到列表：不做请求，也不记失败（下次可见时会重试）。
      return '';
    }
    let store: ImageStore | null = this.thumbStore;
    if (store === null) {
      store = new ImageStore();
      await store.init(this.context());
      this.thumbStore = store;
    }
    return await store.get(client, item.thumbUrl, EhUrl.referer(this.thumbSite));
  }

  /** 移动收藏夹半模态内容（官方 `bindSheet` 承载）。 */
  @Builder
  catSheet() {
    FavCatSheet({
      options: this.sheetOptions(),
      onPick: (cat: number) => {
        if (this.batchMove) {
          this.batchMoveTo(cat).catch((_e: object) => {
            // 错误已在 batchMoveTo 内处理
          });
        } else {
          this.moveTo(cat).catch((_e: object) => {
            // 错误已在 moveTo 内处理
          });
        }
      },
      onCancel: () => {
        this.moveGid = -1;
        this.moveToken = '';
        this.batchMove = false;
      }
    })
  }

  private sheetOptions(): FavCatOption[] {
    const options: FavCatOption[] = [];
    for (let i = 0; i < this.cats.length && i < 10; i++) {
      options.push({ cat: i, name: this.cats[i], count: i < this.counts.length ? this.counts[i] : 0 });
    }
    return options;
  }

  private catOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '全部收藏' }];
    for (let i = 0; i < this.cats.length && i < 10; i++) {
      const count: number = i < this.counts.length ? this.counts[i] : 0;
      options.push({ value: `${this.cats[i]} (${count})` });
    }
    return options;
  }

  private catSelectLabel(): string {
    if (this.favCat < 0) {
      const total: number = this.totalCount();
      return total > 0 ? `全部收藏 (${total})` : '全部收藏';
    }
    const count: number = this.favCat < this.counts.length ? this.counts[this.favCat] : 0;
    return `${this.catNameOf(this.favCat)} (${count})`;
  }

  /** 全部分类的总数（站点给的每类计数之和；没拿到就 0，不显示计数）。 */
  private totalCount(): number {
    let sum: number = 0;
    for (let i = 0; i < this.counts.length; i++) {
      sum += this.counts[i];
    }
    return sum;
  }

  /** 排序选项（与左侧分类同样用 `Select`，工具行观感统一）。 */
  private orderOptions(): SelectOption[] {
    return [{ value: '发布时间' }, { value: '收藏时间' }];
  }

  /** 当前排序的显示名（`Select` 的当前值）。 */
  private orderLabel(): string {
    return this.order === 'f' ? '收藏时间' : '发布时间';
  }

  private orderIndex(): number {
    return this.order === 'f' ? 1 : 0;
  }

  private async load(refresh: boolean): Promise<void> {
    if (this.isLoading) {
      this.isRefreshing = false;
      return;
    }
    this.isLoading = true;
    // 三种请求各有各的指示器（`ui/AGENTS.md` #90）：
    // - 下拉刷新：`RefreshSpinner` 只叠一个圈，**保留旧列表** → 什么都不设；
    // - 第一页重建（初始 / 切分类 / 切排序 / 搜索）：骨架行；
    // - 下一页（滚到底）：列表底部一行「加载中…」。
    if (refresh && !this.isRefreshing) {
      this.reloading = true;
    } else if (!refresh) {
      this.loadingMore = true;
    }
    try {
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      if (!cookies.has('ipb_member_id')) {
        this.items = [];
        this.cats = [];
        this.counts = [];
        this.message = '登录后查看云收藏';
        this.isLoading = false;
        this.isRefreshing = false;
        this.reloading = false;
        this.firstLoad = false;
        return;
      }
      const client: EhClient = this.clientOf(cookies);
      this.thumbClient = client;
      this.thumbSite = site;
      this.message = '加载中…';
      // 后续页面用站点给的 next（`favorites.php?next=…`）；这里只构造第一页。
      const firstUrl: string =
        EhUrl.favorites(site, this.favCat, this.keyword, 0);
      await this.feed.load(firstUrl, refresh);
      this.items = this.feed.items;
      this.message = this.items.length === 0 ? '还没有云收藏' : '';
      this.dataSource.setItems(this.items, this.feed.hasMore);
      // 缩略图不在这里批量补：翻页新来的条目也会自己取（行 `onAppear` 时取一次）。
      // 原来的一次性 `loadMissingThumbs` 只覆盖「本次 load 拿到的这一页」，而且失败是静默的——
      // 那正是「点进去一直是空的、再也出不来」的成因。
    } catch (e) {
      Logger.error('Fav', `cloud load failed: ${e}`);
      this.message = errorText(e as Object);
    }
    this.reloading = false;
    this.loadingMore = false;
    this.isLoading = false;
    this.isRefreshing = false;
    this.firstLoad = false;
  }

  /**
   * 提交收藏内搜索。
   *
   * `value` 必须用 `onSubmit` 回调给的值，不能读 `this.draft`：中文输入法组词期间
   * `onChange` 已经把拼音写进 `draft` 了（第三个参数 `previewText` 才是"还在组词"的标志），
   * 而 `onSubmit` 给的 `value` 是提交后的最终串。只读 `draft` 就会拿「cuimian」去搜，
   * 站点当然 0 条 —— 英文没有组词过程，所以只有中文表现成"不生效"。
   */
  private submitSearch(value: string): void {
    const word: string = submittedKeyword(value, this.draft);
    this.draft = value.length > 0 ? value : this.draft;
    this.keyword = word;
    // 收键盘 + 回顶：搜完要能立刻看到结果第一行。
    this.searchController.stopEditing();
    this.scroller.scrollToIndex(0);
    // 骨架行由 `load(true)` 里的 `reloading` 负责，这里不再手工设 `firstLoad`。
    this.load(true);
  }

  /**
   * 切换排序（发布时间 / 收藏时间）。
   *
   * **只发一个请求**：把 `inline_set=fs_<order>` 拼进列表 URL 本身，站点返回的那一刻
   * 既是「写入偏好」也是「排好序的列表」，直接拿去当第一页——源工程
   * `FavoritesScene.getPageData(taskId, type, page, append)` 就是这么做的。
   *
   * 早先是 `setFavOrder()` + `load(true)` 两个请求：前一个的响应（84 KB 完整列表）被整份丢掉，
   * 真机日志里一次点击 3 个请求 / 约 5 秒。**不要再拆回去**。
   *
   * `inline_set` 的偏好按账号持久化在服务端（真账号实测：设成 `fs_f` 之后不带参数再读也是 `Favorited`），
   * 所以这里不需要「先设置、再取」。
   */
  private async setOrder(next: string): Promise<void> {
    // 同步短路：连点 / 段选自己回填选中态都会再次进来，这些都不是用户意图。
    if (next === this.order || this.isLoading) {
      return;
    }
    const prev: string = this.order;
    this.isLoading = true;
    // 内容整体换掉 → 骨架行（不是转圈）。见 `ui/AGENTS.md` #90 的三处分工。
    this.reloading = true;
    // 回顶：不然数据换掉后还停在老顺序的中间行，看着像"没生效"。
    // 排序变了以后原滚动位置没有意义（第 20 行已经不是原来那条）。
    if (this.items.length > 0) {
      this.scroller.scrollToIndex(0);
    }
    try {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      if (!cookies.has('ipb_member_id')) {
        promptAction.showToast({ message: '登录后查看云收藏' });
        this.reloading = false;
        this.isLoading = false;
        return;
      }
      const site: EhSite = this.settings.site;
      this.message = '加载中…';
      // 先把 URL 定成目标排序再取：`feed.load(refresh: true)` 会用它当第一页。
      // 顺带把 `order` 对齐到目标值——段选的选中态读的就是它。
      this.order = next;
      await this.feed.load(EhUrl.favOrderUrl(site, next, this.favCat, this.keyword, 0), true);
      // 取图用的客户端必须在 `setItems` **之前**就位：行一渲染就 `onAppear` 取图，
      // 晚一步就会拿到上一轮的 client（或 null，那行图永远不出来）。
      this.thumbClient = this.clientOf(cookies);
      this.thumbSite = site;
      this.items = this.feed.items;
      this.message = this.items.length === 0 ? '还没有云收藏' : '';
      this.dataSource.setItems(this.items, this.feed.hasMore);
      this.firstLoad = false;
    } catch (e) {
      Logger.error('Fav', `sort failed: ${e}`);
      promptAction.showToast({ message: '切换排序失败，请重试' });
      // 退回切换前的真实排序（服务端没接受这次切换），否则下拉停在假状态上。
      this.order = prev;
    }
    this.reloading = false;
    this.isLoading = false;
    this.isRefreshing = false;
  }

  private async moveTo(cat: number): Promise<void> {
    const gid: number = this.moveGid;
    const token: string = this.moveToken;
    this.moveGid = -1;
    this.moveToken = '';
    if (gid < 0) {
      return;
    }
    const catName: string = this.catNameOf(cat);
    try {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = this.clientOf(cookies);
      await client.addFavorite(this.settings.site, gid, token, cat);
      promptAction.showToast({ message: `已移动到${catName}` });
      await this.load(true);
    } catch (e) {
      Logger.error('Fav', `move failed gid=${gid}: ${e}`);
      promptAction.showToast({ message: '移动失败，请重试' });
    }
  }

  private confirmDelete(gid: number, token: string, title: string): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '取消收藏',
      message: `确定取消收藏「${title}」吗？`,
      buttons: [{ text: '再想想', color: '#8C8C8C' }, { text: '确定', color: '#3D6BE5' }]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.deleteFav(gid, token).catch((_e: object) => {
          // 错误已在 deleteFav 内处理
        });
      }
    }).catch((_e: object) => {
      // 对话框自身失败不影响列表
    });
  }

  private async deleteFav(gid: number, token: string): Promise<void> {
    try {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = this.clientOf(cookies);
      await client.addFavorite(this.settings.site, gid, token, -1);
      promptAction.showToast({ message: '已取消收藏' });
      await this.load(true);
    } catch (e) {
      Logger.error('Fav', `delete failed gid=${gid}: ${e}`);
      promptAction.showToast({ message: '操作失败，请重试' });
    }
  }

  /** 进/出多选模式。`on` 为真时给一次轻振动（与长按起菜单同一套反馈）。 */
  private setSelectMode(on: boolean): void {
    this.selectMode = on;
    this.selectedGids = [];
    if (!on) {
      this.batchMove = false;
      this.moveGid = -1;
      this.moveToken = '';
    } else {
      // 进多选先收起键盘：搜索框还挂着焦点会让底部动作条被顶上来。
      this.searchController.stopEditing();
    }
  }

  /** 长按一行 = 系统的「进入多选」惯例（振动确认 + 选中当前行）。 */
  private enterSelectMode(gid: number): void {
    hapticTap();
    this.selectMode = true;
    this.batchMove = false;
    this.searchController.stopEditing();
    this.selectedGids = [gid];
  }

  private toggleSelect(gid: number): void {
    this.selectedGids = toggleGid(this.selectedGids, gid);
  }

  private isSelected(gid: number): boolean {
    return this.selectedGids.indexOf(gid) >= 0;
  }

  private allSelected(): boolean {
    return isAllSelected(this.selectedGids, this.items.length);
  }

  private toggleSelectAll(): void {
    if (this.allSelected()) {
      this.selectedGids = [];
      return;
    }
    const all: number[] = [];
    for (let i = 0; i < this.items.length; i++) {
      all.push(this.items[i].gid);
    }
    this.selectedGids = all;
  }

  private tokenOf(gid: number): string {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid === gid) {
        return this.items[i].token;
      }
    }
    return '';
  }

  private catNameOf(cat: number): string {
    for (let i = 0; i < this.cats.length && i < 10; i++) {
      if (i === cat) {
        return this.cats[i];
      }
    }
    return `收藏夹${cat}`;
  }

  /**
   * 批量移动（逐条复用已通的单条收藏接口；源站批量 `ddact` 需重复 key，
   * `postForm` 只支持单值 key，终态等价）。
   */
  private async batchMoveTo(cat: number): Promise<void> {
    const gids: number[] = this.selectedGids.slice();
    this.batchMove = false;
    if (gids.length === 0) {
      return;
    }
    const catName: string = this.catNameOf(cat);
    try {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = this.clientOf(cookies);
      let done: number = 0;
      for (let i = 0; i < gids.length; i++) {
        const token: string = this.tokenOf(gids[i]);
        if (token.length === 0) {
          continue;
        }
        await client.addFavorite(this.settings.site, gids[i], token, cat);
        done += 1;
      }
      promptAction.showToast({
        message: done === gids.length ? `已移动${done}项到${catName}` : `已移动${done}/${gids.length}项，请重试其余`
      });
      this.setSelectMode(false);
      await this.load(true);
    } catch (e) {
      Logger.error('Fav', `batch move failed: ${e}`);
      promptAction.showToast({ message: '移动失败，请重试' });
    }
  }

  private confirmBatchDelete(): void {
    const count: number = this.selectedGids.length;
    if (count === 0) {
      promptAction.showToast({ message: '先选择要删除的收藏' });
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '批量取消收藏',
      message: `确定取消收藏选中的 ${count} 项吗？`,
      buttons: [{ text: '再想想', color: '#8C8C8C' }, { text: '确定', color: '#3D6BE5' }]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.batchDeleteFav().catch((_e: object) => {
          // 错误已在 batchDeleteFav 内处理
        });
      }
    }).catch((_e: object) => {
      // 对话框自身失败不影响列表
    });
  }

  /** 批量删除（逐条复用单条接口，语义同 `batchMoveTo`）。 */
  private async batchDeleteFav(): Promise<void> {
    const gids: number[] = this.selectedGids.slice();
    if (gids.length === 0) {
      return;
    }
    try {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = this.clientOf(cookies);
      let done: number = 0;
      for (let i = 0; i < gids.length; i++) {
        const token: string = this.tokenOf(gids[i]);
        if (token.length === 0) {
          continue;
        }
        await client.addFavorite(this.settings.site, gids[i], token, -1);
        done += 1;
      }
      promptAction.showToast({
        message: done === gids.length ? `已取消收藏${done}项` : `已取消${done}/${gids.length}项，请重试其余`
      });
      this.setSelectMode(false);
      await this.load(true);
    } catch (e) {
      Logger.error('Fav', `batch delete failed: ${e}`);
      promptAction.showToast({ message: '操作失败，请重试' });
    }
  }

  /** 行尾勾选圈：多选态才显示（非多选态这里不占位，行宽和其他列表一致）。 */
  @Builder
  selectMark(gid: number) {
    SymbolGlyph(this.isSelected(gid) ? $r('sys.symbol.checkmark_circle_fill_1') : $r('sys.symbol.circle'))
      .fontSize(22)
      .fontColor([this.isSelected(gid)
        ? $r('sys.color.brand') : $r('app.color.text_secondary')])
      .width(TOUCH_MIN)
      .height(TOUCH_MIN)
      .padding(11)
      .accessibilityText(this.isSelected(gid) ? '已选中' : '未选中')
      .onClick(() => {
        this.toggleSelect(gid);
      })
  }

  /** 列表行：与首页/搜索同一形态（`GalleryRow`），多选态在右侧加勾选圈。 */
  @Builder
  favRow(item: GalleryRowItem) {
    Row({ space: 4 }) {
      GalleryRow({ item: item })
        .layoutWeight(1)
        .onAppear(() => {
          this.ensureThumb(item);
        })
        // 长按 = 进入多选（系统惯例）；单击在多选态是切换选中，否则进详情。
        .gesture(
          LongPressGesture({ repeat: false, duration: 400 })
            .onAction(() => {
              if (!this.selectMode) {
                this.enterSelectMode(item.gid);
              }
            })
        )
        .onClick(() => {
          if (this.selectMode) {
            this.toggleSelect(item.gid);
          } else {
            pushGalleryDetail(this.getUIContext(), this.pageStack, item);
          }
        })
      if (this.selectMode) {
        this.selectMark(item.gid)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 行尾横滑动作（官方 `ListItem.swipeAction`）。
   *
   * 官方这个接口只接受 `builder`（纯自绘），没有 HDS `swipeActionOptions` 那种 `icons: SymbolGlyphModifier`
   * 的现成能力——所以这里自己画，但**只画圆形图标底 + 语义图标**，不带文字：
   * 系统列表的横滑动作惯例就是图标（文字要把动作区撑得很宽，划出来很难看）。
   *
   * 为什么用 ArkUI 标准版而不是 HDS 的 `swipeActionOptions`：行内容已经是 `GalleryRow` 自带卡片，
   * 再套 `HdsListItem` 会变成「卡片套卡片」；而 HDS 横滑动效是 `HdsListItem` 的属性，普通 `ListItem` 用不了。
   */
  @Builder
  rowSwipe(item: GalleryRowItem) {
    // 多选态不给横滑：那时单击是"选中"，两种手势会互相打架。
    if (!this.selectMode) {
      Row({ space: 8 }) {
        this.swipeIconButton($r('sys.symbol.square_and_pencil'), '移动到收藏夹',
          $r('sys.color.brand'), () => {
            this.moveGid = item.gid;
            this.moveToken = item.token;
          })
        this.swipeIconButton($r('sys.symbol.trash'), '取消收藏',
          $r('app.color.danger'), () => {
            this.confirmDelete(item.gid, item.token, item.title);
          })
      }
      .height('100%')
      .padding({ left: 8, right: 12 })
      .backgroundColor($r('app.color.bg_primary'))
    }
  }

  /** 横滑动作的单个图标按钮（圆形底 + 语义图标；与系统列表的划出动作同构）。 */
  @Builder
  swipeIconButton(icon: Resource, label: string, bg: ResourceColor, action: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([Color.White])
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor(bg)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(label)
    .onClick(action)
  }

  /**
   * 顶部工具行：分类 + 排序，两个 `Select` **等宽**。
   *
   * 排序走过三版：`图标 + bindMenu` → 胶囊段选 → `Select`。前两版被真机否掉：
   * 图标那版当前值不可见；段选这版放不下（右侧溢出，标签被省略号吃掉，见 #88 / #89）。
   * 现在两个控件同种形态、等宽各占一半，视觉上成组。
   *
   * **多选态的「全选」只留在标题栏菜单**，这里不放第二个（用户报过"有两个全选按钮"）：
   * 官方把页面级动作放标题栏，工具行只负责筛选与排序。
   * 多选时两个下拉保留但禁用——布局不跳，也不会在选中途中把列表换掉。
   */
  @Builder
  controlsRow() {
    Row({ space: 8 }) {
      // 分类（选项多 → `Select`）。等宽而不是写死宽度：写死会把右边顶出屏幕（#88）。
      Select(this.catOptions())
        .selected(this.favCat + 1)
        .value(this.catSelectLabel())
        .height(36)
        .layoutWeight(1)
        // 重建中 / 多选态都锁住：前者点了会被 `isLoading` 短路（像"点了没反应"），
        // 后者会把选中集与换掉的内容错位。
        .enabled(!this.reloading && !this.selectMode)
        .onSelect((index: number, _value: string) => {
          if (index - 1 !== this.favCat) {
            this.favCat = index - 1;
            this.setSelectMode(false);
            this.load(true);
          }
        })
      // 排序：与分类同一种 `Select`、同样等宽。
      Select(this.orderOptions())
        .selected(this.orderIndex())
        .value(this.orderLabel())
        .height(36)
        .layoutWeight(1)
        .enabled(!this.reloading && !this.selectMode)
        .onSelect((index: number, _value: string) => {
          // `Select` 点中当前项也会回调，那不是用户意图。
          if (index !== this.orderIndex()) {
            this.setOrder(index === 1 ? 'f' : 'p').catch((_e: object) => {
              // 错误已在 setOrder 内处理
            });
          }
        })
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 8, bottom: 4 })
  }

  /** `Refresh` 内置区域留空：圈由 `RefreshSpinner` 画在内容起始线（见 `ui/RefreshSpinner.ets`）。 */
  @Builder
  emptyRefreshArea() {
    Column().width('100%')
  }

  /**
   * 刷新圈的内容起始线 = **标题栏下沿**（`safeTop + TITLE_BAR_H` 之后的空档）。
   *
   * 下拉时列表整体下移，露出来的空白就在标题栏下面这一块；圈必须画在这里。
   * **不要**再加工具行 / 搜索行的高度：收藏页把分类、排序、搜索框都放进了 `List`，
   * 它们会跟着一起被拉下去，所以在列表外看「内容起始线」仍然是标题栏下沿。
   * 加了 48+4 的后果是圈落在搜索框上（`y≈516px` vs 搜索框 529），肉眼看不到。
   * 与 `DiscoverListPage` / `TopListPage` / `SearchPage` 保持同一个公式。
   */
  private spinnerTop(): number {
    return this.windowState.safeTop + TITLE_BAR_H + 8;
  }

  /** 首屏骨架行（共享组件，六个列表同一形态；见 `ui/GalleryRowSkeleton.ets`）。 */
  @Builder
  rowSkeleton() {
    GalleryRowSkeleton()
  }

  /**
   * 空态 / 错误态：图标 + 主文案 + 说明 + 主按钮。
   *
   * 只有一行灰字的空态等于把用户丢在原地：他既不知道发生了什么，也没有下一步可做。
   * 三种情况分别给不同的动作：
   * - 未登录 → 「去登录」（登录入口在设置页 `ui/SettingsPage.ets`）；
   * - 还没有收藏 → 只给说明，引导他在详情页收藏（本页没有可跳的"浏览"入口）；
   * - 其他（网络/解析失败）→ 「重试」，否则只能退出重进。
   */
  @Builder
  stateView() {
    Column({ space: 12 }) {
      SymbolGlyph(this.stateIcon())
        .fontSize(48)
        .fontColor([$r('app.color.text_secondary')])
        .opacity(0.6)
      Text(this.message)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
      if (this.stateHint().length > 0) {
        Text(this.stateHint())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }
      if (this.stateAction().length > 0) {
        Button(this.stateAction())
          .fontSize(14)
          .height(36)
          .padding({ left: 24, right: 24 })
          .onClick(() => {
            if (this.notLoggedIn()) {
              this.pageStack?.pushPathByName('设置', undefined);
            } else {
              this.load(true);
            }
          })
      }
    }
    .width('100%')
    .padding({ top: 88, left: 32, right: 32 })
  }

  private notLoggedIn(): boolean {
    return this.message === '登录后查看云收藏';
  }

  private stateIcon(): Resource {
    if (this.notLoggedIn()) {
      return $r('sys.symbol.person');
    }
    if (this.message === '还没有云收藏') {
      return $r('sys.symbol.heart');
    }
    return $r('sys.symbol.exclamationmark_circle');
  }

  private stateHint(): string {
    if (this.notLoggedIn()) {
      return '用 Web 登录或手动填入 Cookie 后即可查看云端收藏。';
    }
    if (this.message === '还没有云收藏') {
      return '在画廊详情页点心形按钮，收藏会出现在这里。';
    }
    return '检查网络或站点设置后重试。';
  }

  /** 空字符串 = 不给按钮（空收藏没有可跳的目标，只有说明）。 */
  private stateAction(): string {
    if (this.notLoggedIn()) {
      return '去登录';
    }
    if (this.message === '还没有云收藏') {
      return '';
    }
    return '重试';
  }

  /**
   * 多选态的底部动作条（官方 `HdsActionBar`：悬浮胶囊 + 系统材质）。
   * 与详情页底栏同一档位，不再是一行裸文字。
   */
  @Builder
  batchBar() {
    HdsActionBar({
      startButtons: [new ActionBarButton({
        baseIcon: $r('sys.symbol.square_and_pencil'),
        accessibilityText: '移动到收藏夹',
        id: 'fav-batch-move',
        onClick: () => {
          if (this.selectedGids.length === 0) {
            promptAction.showToast({ message: '先选择要移动的收藏' });
            return;
          }
          this.batchMove = true;
        }
      })],
      endButtons: [new ActionBarButton({
        baseIcon: $r('sys.symbol.trash'),
        accessibilityText: '取消收藏',
        id: 'fav-batch-delete',
        onClick: () => {
          this.confirmBatchDelete();
        }
      })],
      actionBarStyle: new ActionBarStyle({
        height: LengthMetrics.vp(56),
        backgroundColor: ColorMetrics.resourceColor(Color.Transparent),
        backgroundBlurStyle: BlurStyle.COMPONENT_ULTRA_THICK
      }),
      isExpand: false,
      blurStrategy: BlurStrategy.ADAPTIVE
    })
  }

  /** 标题栏菜单：多选态给「全选 / 退出」，否则不给（排序在多选外一直由工具行承载）。 */
  private titleMenu(): HdsNavigationMenuContentOptions | undefined {
    if (!this.selectMode) {
      return undefined;
    }
    const all: boolean = this.allSelected();
    const allIcon: SymbolGlyphModifier = all
      ? new SymbolGlyphModifier($r('sys.symbol.circle'))
      : new SymbolGlyphModifier($r('sys.symbol.checkmark_circle_fill_1'));
    const exitIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.xmark'));
    return {
      value: [{
        content: {
          icon: allIcon,
          label: all ? '取消全选' : '全选',
          action: () => {
            this.toggleSelectAll();
          }
        }
      }, {
        content: {
          icon: exitIcon,
          label: '退出多选',
          action: () => {
            this.setSelectMode(false);
          }
        }
      }]
    };
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          Stack({ alignContent: Alignment.Top }) {
            Refresh({ refreshing: $$this.isRefreshing, builder: this.emptyRefreshArea() }) {
              // 行间隔只由 ListItem 的 `padding({bottom: CARD_GAP})` 提供（**不要**再给 `List` 的 `space`，
              // 两者叠加会变成 CARD_GAP + space，比其他列表大一圈——`ui/AGENTS.md` #80）。
              List({ scroller: this.scroller }) {
                // 顶部避让放进滚动内容（内容钻到标题栏下，渐变模糊才生效）。
                ListItem() {
                  Column().height(this.windowState.safeTop + TITLE_BAR_H)
                }
                // 分类 / 排序（或多选的全选）/ 搜索框放进列表：滚动时一起钻到标题栏下。
                ListItem() {
                  this.controlsRow()
                }
                ListItem() {
                  Row() {
                    Search({ value: this.draft, placeholder: '收藏内搜索', controller: this.searchController })
                      .layoutWeight(1)
                      .enabled(!this.selectMode)
                      // 与搜索页同一形态：提交用组件原生的框内文字按钮（图标版整行不协调）。
                      .searchButton('搜索')
                      .onChange((value: string) => {
                        // 只记草稿；生效点是回车/搜索按钮（见 `submitSearch`）。
                        this.draft = value;
                      })
                      .onSubmit((value: string) => {
                        this.submitSearch(value);
                      })
                      .onClick(() => {
                        // 点已经填了字的搜索框：全选，方便直接覆盖重搜。
                        if (this.draft.length > 0) {
                          this.searchController.caretPosition(this.draft.length);
                        }
                      })
                  }
                  .width('100%')
                  .padding({ left: PAGE_PADDING, right: PAGE_PADDING, bottom: 4 })
                }
                // 骨架行：内容正在整体重建时占位（首屏 / 切分类 / 切排序 / 提交搜索）。
                // **必须同时不渲染真实行**，否则骨架与旧数据会一起出现。
                if (this.reloading) {
                  Repeat(SKELETON_ROW_INDICES)
                    .each((_ri: RepeatItem<number>) => {
                      ListItem() {
                        this.rowSkeleton()
                      }
                      .padding({ left: PAGE_PADDING, right: PAGE_PADDING, bottom: CARD_GAP })
                    })
                    .key((i: number) => `sk-${i}`)
                } else {
                  LazyForEach(this.dataSource, (item: GalleryRowItem) => {
                    ListItem() {
                      this.favRow(item)
                    }
                    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, bottom: CARD_GAP })
                    // 行尾横滑：移动 / 取消收藏（多选态由 builder 内部关掉）。
                    .swipeAction({ end: this.rowSwipe(item) })
                  }, (item: GalleryRowItem) => `${item.gid}`)
                  // 下一页在飞：列表底部一行提示（标准 load-more 形态）。
                  if (this.loadingMore) {
                    ListItem() {
                      Row({ space: 8 }) {
                        LoadingProgress()
                          .width(16)
                          .height(16)
                          .color($r('app.color.text_secondary'))
                        Text('加载中…')
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                      }
                      .width('100%')
                      .justifyContent(FlexAlign.Center)
                      .padding({ top: 4, bottom: 12 })
                    }
                  }
                  // 空态 / 错误：作为 ListItem 放在 List 里（放外面会被 `layoutWeight` 挤成半屏）。
                  if (!this.firstLoad && this.items.length === 0 && this.message.length > 0) {
                    ListItem() {
                      this.stateView()
                    }
                  }
                }
                // 多选态底部动作条会盖住最后一行：留出让位。
                if (this.selectMode) {
                  ListItem() {
                    Column().height(this.windowState.safeBottom + 96)
                  }
                }
              }
              .width('100%')
              .height('100%')
              .cachedCount(4)
              // 预取：滚到尾部窗口就问一次（`getData` 不再有副作用）。
              .onScrollIndex((_start: number, end: number) => {
                if (shouldFetchMore(this.items.length, end + PREFETCH_TAIL, this.feed.hasMore, this.isLoading)) {
                  this.load(false);
                }
              })
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
            }
            .onRefreshing(() => {
              // 多选态不许下拉刷新：重新拉列表会让选中集与换掉的内容错位。
              // `Refresh` 没有 `enabled`，只能在回调里取消（复位绑定变量即可收起）。
              if (this.selectMode) {
                this.isRefreshing = false;
                return;
              }
              this.load(true);
            })
            .onOffsetChange((v: number) => {
              this.pullOffset = v;
            })
            .onStateChange((s: RefreshStatus) => {
              if (s === RefreshStatus.Done) {
                this.pullOffset = 0;
              }
            })
            .layoutWeight(1)
            RefreshSpinner({
              pullOffset: this.pullOffset,
              isRefreshing: this.isRefreshing,
              // **不传 `busy`**。它只服务「下拉刷新」这一种场景：
              // - 初始进入 / 切分类 / 切排序 / 搜索时，内容区有骨架行或已有列表，圈是重复信息；
              // - 而且它落点在标题栏下沿，那几个场景列表没被下拉，圈会**压在工具行上**
              //   （真机 spinnerTop=368px、工具行 367..489px）。程序化请求的反馈在工具行行尾（#90）。
              top: this.spinnerTop()
            })
          }
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.bg_primary'))
        .onAppear(() => {
          this.load(true);
        })

        // 多选底部动作条：悬浮胶囊（官方 HdsActionBar + 系统材质）。
        if (this.selectMode) {
          Column() {
            this.batchBar()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: 12 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
        }
      }
      .width('100%')
      .height('100%')
      // 移动收藏夹：官方半模态 + 系统材质（原自绘遮罩浮层已删）。
      .bindSheet(this.moveGid >= 0 || this.batchMove, this.catSheet(), {
        title: { title: '移动到收藏夹' },
        // 内容是 List（无固有高度，`FIT_CONTENT` 量不出来）：半屏起步，可上拖到全屏。
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        // 半模态材质必须组件级设置（应用级开关不覆盖 `bindSheet`，见 `Materials.ets`）。
        backgroundColor: sheetBackdrop().backgroundColor,
        systemMaterial: sheetBackdrop().material,
        onDisappear: () => {
          this.moveGid = -1;
          this.moveToken = '';
          this.batchMove = false;
        }
      })
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      style: navTitleBarStyle(),
      content: {
        // 多选态标题变成计数（系统惯例：标题栏承载"已选 N 项"）。
        title: { mainTitle: this.selectMode ? `已选 ${this.selectedGids.length} 项` : '收藏' },
        menu: this.titleMenu()
      }
    })
    .bindToScrollable([this.scroller])
    // 多选态返回键 = 退出多选（不直接退出页面）。
    .onBackPressed(() => {
      if (this.selectMode) {
        this.setSelectMode(false);
        return true;
      }
      return false;
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
    })
  }
}
