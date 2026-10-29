import { common } from '@kit.AbilityKit';
import { AppStorageV2, PersistenceV2, promptAction, ChipV2, ChipV2Label, ChipV2Options, ChipV2Size, ColorMetrics, LengthMetrics, SubHeaderV2, SubHeaderV2Title } from '@kit.ArkUI';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { GalleryInfo } from '../model/GalleryInfo';
import { SearchKind, SearchParam } from '../model/SearchParam';
import { Logger } from '../common/Logger';
import { errorText } from '../common/ErrorText';
import { AppSettings } from '../state/AppSettings';
import { WindowState } from '../state/WindowState';
import { HdsNavDestination, HideMode } from '@kit.UIDesignKit';
import { GalleryRow, GalleryRowItem, loadMissingThumbs, pushGalleryDetail } from './GalleryRow';
import { fCatsMask, excludedFromSelected, encodeAdvance, ALL_CATS, languageQueryOf, SEARCH_LANGUAGES, exclusionQueryOf, SearchFilters } from '../search/SearchQuery';
import { FilterDao } from '../db/dao/FilterDao';
import { DbHelper } from '../db/DbHelper';
import { Filter } from '../model/Filter';
import { PagedDataSource } from '../common/PagedList';
import { QuickSearchDao } from '../db/dao/QuickSearchDao';
import { QuickSearch } from '../model/QuickSearch';
import { hasSavedKeyword } from '../search/QuickSearchQuery';
import { QuickSearchSheet } from './QuickSearchSheet';
import { CARD_GAP, CARD_RADIUS, PAGE_PADDING, SHEET_MATERIAL, TOUCH_MIN } from './Materials';
import { navTitleBarStyle, TITLE_BAR_H } from './NavStyle';
import { RefreshSpinner } from './RefreshSpinner';

/** 搜索范围 chip 项（`f_sname/f_stags/f_sdesc/f_storr`；选中 = 只搜该范围；网站英文原文）。 */
interface ScopeItem {
  label: string;
  key: string;
}

const SCOPES: ScopeItem[] = [
  { label: 'Gallery Name', key: 'title' },
  { label: 'Gallery Tags', key: 'tags' },
  { label: 'Gallery Description', key: 'desc' },
  { label: 'Torrents', key: 'torrents' }
];

/** 最低星级档（源 spinner `position + 2`）。 */
const STARS: number[] = [2, 3, 4, 5];

/** 语言下拉选项（首位 `all` = 不限语言；其余为站点原文，保持全英文避免中英割裂）。 */
const LANG_ANY: string = 'all';
const LANG_OPTIONS: string[] = [LANG_ANY].concat(SEARCH_LANGUAGES);

/** `Select` 的官方选项模型（与 `LANG_OPTIONS` 同序；`Select` 只要 `{ value }`）。 */
function langSelectOptions(): SelectOption[] {
  const out: SelectOption[] = [];
  for (let i = 0; i < LANG_OPTIONS.length; i++) {
    out.push({ value: LANG_OPTIONS[i] });
  }
  return out;
}

/** 标题栏底部功能区：单行搜索行高度（vp）。 */
const SEARCH_ROW_H: number = 52;
/** 收起态筛选摘要行高度（vp）。 */
const SUMMARY_ROW_H: number = 40;

/** 分类 chip 项（位值对照源 `EhConfig`；点亮 = 选中该分类 → 换算排除集发 `f_cats`；网站英文原文）。 */
interface CatItem {
  label: string;
  bit: number;
}

const CATS: CatItem[] = [
  { label: 'DOUJINSHI', bit: 0x2 },
  { label: 'MANGA', bit: 0x4 },
  { label: 'ARTIST CG', bit: 0x8 },
  { label: 'GAME CG', bit: 0x10 },
  { label: 'IMAGE SET', bit: 0x20 },
  { label: 'COSPLAY', bit: 0x40 },
  { label: 'ASIAN PORN', bit: 0x80 },
  { label: 'NON-H', bit: 0x100 },
  { label: 'WESTERN', bit: 0x200 },
  { label: 'MISC', bit: 0x1 }
];

/** 范围短名（摘要行用；`f_s*` 语义不变，仅展示从简）。 */
function scopeShort(key: string): string {
  if (key === 'title') {
    return '名称';
  }
  if (key === 'tags') {
    return '标签';
  }
  if (key === 'desc') {
    return '描述';
  }
  return '种子';
}

/**
 * 搜索页（关键词 / 上传者 / 标签三态经 `SearchParam.kind` 进入；结果页与首页同构，复用 `GalleryListParser`）。
 * 状态与首页隔离：独立 `page`/`items`。
 */
@ComponentV2
export struct SearchPage {
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  /** 系统安全区（内容顶部避让 = safeTop + 标题栏 + 功能区）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  @Local showQuickSearch: boolean = false;
  /** 语言 chip 单选（`language:xxx` 站点原文；空 = 不过滤）。 */
  @Local selectedLang: string = '';
  /** 启用的屏蔽规则（搜索 `-` chips 用；`load` 内刷新）。 */
  @Local activeRules: Filter[] = [];
  /** 本次搜索忽略的排除项（`mode:text` 键；`applyParam` 重置）。 */
  @Local ignoredExclusions: string[] = [];
  @Local query: string = '';
  @Local kind: SearchKind = 'keyword';
  @Local pageTitle: string = '搜索';
  @Local items: GalleryRowItem[] = [];
  @Local isRefreshing: boolean = false;
  /** 当前下拉距离（vp，来自 `Refresh.onOffsetChange`），只用于刷新圈的淡入。 */
  @Local pullOffset: number = 0;
  @Local message: string = '';
  /** 点亮的分类位（正选语义，默认 10 位全亮；切换后重置 `page=0` 重搜）。数组只整体替换，保证 `@Local` 刷新。 */
  @Local selectedBits: number[] = ALL_CATS.slice();
  /** 搜索范围（`SCOPES` 的 key 子集；空 = 不限范围）。 */
  @Local scopes: string[] = [];
  /** 语言过滤（`f_sfl`）。 */
  @Local langFilter: boolean = false;
  /** 最低星级（`-1` = 关，否则 2/3/4/5）。 */
  @Local minRating: number = -1;
  /** 官方高级搜索：只搜有种子（`f_sto`）。 */
  @Local onlyTorrents: boolean = false;
  /** 官方高级搜索：忽略站点默认过滤（`f_sfl/f_sfu/f_sft`）。 */
  @Local ignoreFilters: boolean = false;
  /** 官方高级搜索：页数区间（空 = 不限）。 */
  @Local pageFromText: string = '';
  @Local pageToText: string = '';
  /** 高级选项默认折叠（低频）。 */
  @Local advancedExpanded: boolean = false;
  /** 高级筛选展开态：首进展开，提交搜索后自动收起（摘要行留在标题栏，点之再展开）。 */
  @Local filtersExpanded: boolean = true;
  private page: number = 0;
  private isLoading: boolean = false;
  /** 结果列表滚动器（折叠/展开筛选时回顶用；不再有吸顶 header）。 */
  private listScroller: Scroller = new Scroller();
  /** 懒加载数据源（`LazyForEach` 官方范式；`getData` 进入尾部窗口即预取下一页）。 */
  private dataSource: PagedDataSource<GalleryRowItem> =
    new PagedDataSource<GalleryRowItem>(() => {
      this.load(false);
    }, () => {
      return this.isLoading;
    });
  private pageStack: NavPathStack | undefined = undefined;
  /** 搜索框控制器（官方收键盘手段：`SearchController.stopEditing()`；见 `search.d.ts:74`）。 */
  private searchController: SearchController = new SearchController();

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  /** 标题栏底部功能区高度：单行搜索恒在，收起态多一行摘要。 */
  @Computed get headerHeight(): number {
    return SEARCH_ROW_H + (this.filtersExpanded ? 0 : SUMMARY_ROW_H);
  }

  /** 内容区顶部避让（状态栏 + 标题栏主标题 + 底部功能区；不再用吸顶 header，内容不钻到栏下）。 */
  @Computed get contentTop(): number {
    return this.windowState.safeTop + TITLE_BAR_H + this.headerHeight;
  }

  /** 生效中的排除规则数（被本次忽略的不算，与 `exclusionQueryOf` 语义一致）。 */
  @Computed get activeExclusions(): number {
    let count: number = 0;
    for (let i = 0; i < this.activeRules.length; i++) {
      if (this.ignoredExclusions.indexOf(this.exclusionKey(this.activeRules[i])) < 0) {
        count += 1;
      }
    }
    return count;
  }

  /** 收起态摘要：只列**非默认**条件（默认全分类/全范围/不限语言/不限星级不刷屏）；无则空。 */
  @Computed get activeChips(): string[] {
    const chips: string[] = [];
    if (this.selectedBits.length !== ALL_CATS.length) {
      chips.push(`${this.selectedBits.length}/${ALL_CATS.length} 分类`);
    }
    if (this.scopes.length > 0) {
      const names: string[] = [];
      for (let i = 0; i < SCOPES.length; i++) {
        if (this.scopes.indexOf(SCOPES[i].key) >= 0) {
          names.push(scopeShort(SCOPES[i].key));
        }
      }
      chips.push(names.join('/'));
    }
    if (this.selectedLang.length > 0) {
      chips.push(this.selectedLang);
    }
    if (this.minRating > 0) {
      chips.push(`${this.minRating}★+`);
    }
    if (this.activeExclusions > 0) {
      chips.push(`${this.activeExclusions} 排除`);
    }
    return chips;
  }

  /** 提交搜索（键盘回车 / 蓝「搜索」/ 快搜运行）：收键盘 + 收筛选 + 回顶，再重搜。 */
  private submitSearch(): void {
    this.showQuickSearch = false;
    this.searchController.stopEditing();
    if (this.filtersExpanded) {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
        this.filtersExpanded = false;
        this.listScroller.scrollToIndex(0);
      });
    }
    this.load(true);
  }

  /** 摘要 chip → 重新展开高级选项并回顶（与折叠互为反向动画）。 */
  private expandFilters(): void {
    if (this.filtersExpanded) {
      return;
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.filtersExpanded = true;
      this.listScroller.scrollToIndex(0);
    });
  }

  /** 展开态「完成」→ 收起（不重搜：条件已即时生效）。 */
  private collapseFilters(): void {
    if (!this.filtersExpanded) {
      return;
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.filtersExpanded = false;
    });
  }

  /** 存为快速搜索（仅 keyword 态；名取当前查询）。 */
  private async saveQuick(): Promise<void> {
    const keyword: string = this.query.trim();
    if (keyword.length === 0) {
      promptAction.showToast({ message: '先输入关键词或条件' });
      return;
    }
    try {
      await DbHelper.init(this.context());
      const exist: QuickSearch[] = await QuickSearchDao.queryAll();
      if (hasSavedKeyword(exist, keyword)) {
        promptAction.showToast({ message: '快搜里已有该搜索' });
        return;
      }
      await QuickSearchDao.insert({
        id: 0,
        name: this.kind === 'keyword' ? keyword : (this.pageTitle.length > 0 ? this.pageTitle : keyword),
        mode: this.kind === 'uploader' ? 1 : (this.kind === 'tag' ? 2 : 0),
        category: fCatsMask(excludedFromSelected(this.selectedBits, ALL_CATS)),
        keyword: keyword,
        language: this.selectedLang,
        advanceSearch: encodeAdvance(this.scopes, this.langFilter),
        minRating: this.minRating, pageFrom: -1, pageTo: -1, time: Date.now()
      });
      promptAction.showToast({ message: '已存到快搜' });
    } catch (e) {
      Logger.error('QSearch', `save failed: ${e}`);
      promptAction.showToast({ message: '保存失败，请重试' });
    }
  }

  /** 路由参数（含快搜运行带条件）→ 本页状态；缺字段回退默认。 */
  private applyParam(param: SearchParam): void {
    this.query = param.query;
    this.kind = param.kind;
    this.pageTitle = param.title.length > 0 ? param.title : '搜索';
    // 单次排除是临时筛选（快搜记录不存）；语言 chip 现在随快搜落库，缺省清空。
    this.selectedLang = '';
    this.ignoredExclusions = [];
    this.onlyTorrents = false;
    this.ignoreFilters = false;
    this.pageFromText = '';
    this.pageToText = '';
    this.advancedExpanded = false;
    if (param.selectedBits !== undefined) {
      this.selectedBits = param.selectedBits.slice();
    }
    if (param.scopes !== undefined) {
      this.scopes = param.scopes.slice();
    }
    if (param.language !== undefined) {
      this.selectedLang = param.language;
    }
    if (param.langFilter !== undefined) {
      this.langFilter = param.langFilter;
    }
    if (param.minRating !== undefined) {
      this.minRating = param.minRating;
    }
  }

  /** 页数输入 → 数字（空/非法/≤0 视为不限 = -1）。 */
  private static parsePage(text: string): number {
    const n: number = Number.parseInt(text.trim(), 10);
    return isNaN(n) || n <= 0 ? -1 : n;
  }

  /** 把查询拆成 chip：空格分隔，引号内的空格不拆（`-other:"ai generated"` 算一个）。 */
  private static splitTokens(text: string): string[] {
    const out: string[] = [];
    const src: string = text.trim();
    let cur: string = '';
    let inQuote: boolean = false;
    for (let i = 0; i < src.length; i++) {
      const ch: string = src.charAt(i);
      if (ch === '"') {
        inQuote = !inQuote;
        cur += ch;
        continue;
      }
      if (ch === ' ' && !inQuote) {
        if (cur.length > 0) {
          out.push(cur);
          cur = '';
        }
        continue;
      }
      cur += ch;
    }
    if (cur.length > 0) {
      out.push(cur);
    }
    return out;
  }

  @Computed get queryChips(): string[] {
    return SearchPage.splitTokens(this.query);
  }

  /** 点 chip：包含 ↔ 排除（只改 query，立即重搜）。 */
  private toggleChip(index: number): void {
    const tokens: string[] = this.queryChips;
    if (index < 0 || index >= tokens.length) {
      return;
    }
    const token: string = tokens[index];
    tokens[index] = token.startsWith('-') ? token.substring(1) : `-${token}`;
    this.query = tokens.join(' ');
    this.load(true);
  }

  private removeChip(index: number): void {
    const tokens: string[] = this.queryChips;
    if (index < 0 || index >= tokens.length) {
      return;
    }
    tokens.splice(index, 1);
    this.query = tokens.join(' ');
    this.load(true);
  }

  private buildUrl(site: EhSite): string {    // 三态统一走 `f_search`（EHWiki：`uploader:`/`title:`/`tag:` 均为合法 qualifier）。
    // 上传者恒加引号精确匹配；tag 态查询串已由入口写成正规语法 `namespace:"tag$"`（见 `exactTagQuery`），
    // 这里**原样发**——再包一层会得到 `parody:""blue archive$"` 这种坏串。
    let keyword: string;
    if (this.kind === 'uploader') {
      keyword = `uploader:"${this.query.trim()}"`;
    } else {
      keyword = this.query.trim();
    }
    const all: number[] = ALL_CATS.slice();
    const bits: number[] = excludedFromSelected(this.selectedBits, all);
    const langFrag: string = languageQueryOf(this.selectedLang);
    if (langFrag.length > 0) {
      keyword = keyword.length > 0 ? `${keyword} ${langFrag}` : langFrag;
    }
    const exclFrag: string = exclusionQueryOf(this.activeRules, this.ignoredExclusions);
    if (exclFrag.length > 0) {
      keyword = keyword.length > 0 ? `${keyword} ${exclFrag}` : exclFrag;
    }
    const filters: SearchFilters = {
      inTitle: this.scopes.indexOf('title') >= 0,
      inTags: this.scopes.indexOf('tags') >= 0,
      inDesc: this.scopes.indexOf('desc') >= 0,
      inTorrents: this.scopes.indexOf('torrents') >= 0,
      language: this.langFilter,
      minRating: this.minRating,
      onlyTorrents: this.onlyTorrents,
      ignoreFilters: this.ignoreFilters,
      pageFrom: SearchPage.parsePage(this.pageFromText),
      pageTo: SearchPage.parsePage(this.pageToText)
    };
    return EhUrl.search(site, keyword, this.page, fCatsMask(bits), filters);
  }

  private toRowItems(list: GalleryInfo[]): GalleryRowItem[] {
    const mapped: GalleryRowItem[] = [];
    for (let i = 0; i < list.length; i++) {
      const item: GalleryRowItem = new GalleryRowItem();
      item.gid = list[i].gid;
      item.token = list[i].token;
      item.title = list[i].title;
      item.uploader = list[i].uploader;
      item.thumbUrl = list[i].thumb;
      item.category = list[i].category;
      item.rating = list[i].rating;
      item.posted = list[i].posted;
      item.simpleLanguage = list[i].simpleLanguage;
      item.pages = list[i].pages;
      mapped.push(item);
    }
    return mapped;
  }

  /** 排除规则重读（每次搜索自动拼 `-…` 查询条件；不再本地过滤列表）。 */
  private async reloadRules(): Promise<void> {
    if (this.kind !== 'keyword') {
      this.activeRules = [];
      return;
    }
    try {
      await DbHelper.init(this.context());
      const all: Filter[] = await FilterDao.queryAll();
      this.activeRules = all.filter((f: Filter) => f.enable);
    } catch (e) {
      Logger.error('Block', `rules load failed: ${e}`);
    }
  }

  private async load(refresh: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    // 规则只在刷新/首载时重读；翻页复用已缓存的 activeRules（免每页一次 DB 读）。
    if (refresh) {
      await this.reloadRules();
    }
    const exclFrag: string = exclusionQueryOf(this.activeRules, this.ignoredExclusions);
    if (this.kind === 'keyword' && this.query.trim().length === 0 &&
      this.selectedLang.length === 0 && exclFrag.length === 0) {
      this.message = '';
      this.isRefreshing = false;
      return;
    }
    this.isLoading = true;
    if (refresh) {
      this.page = 0;
    }
    try {
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      this.message = '搜索中…';
      const url: string = this.buildUrl(site);
      const list: GalleryInfo[] = await client.getGalleryList(site, url, this.settings.thumbSize);
      const mapped: GalleryRowItem[] = this.toRowItems(list);
      if (refresh) {
        this.items = mapped;
      } else {
        const appended: GalleryRowItem[] = [];
        for (let i = 0; i < mapped.length; i++) {
          let exists: boolean = false;
          for (let j = 0; j < this.items.length; j++) {
            if (this.items[j].gid === mapped[i].gid) {
              exists = true;
              break;
            }
          }
          if (!exists) {
            appended.push(mapped[i]);
          }
        }
        this.items = this.items.concat(appended);
      }
      this.message = this.items.length === 0 ? '没有找到相关画廊' : '';
      this.dataSource.setItems(this.items, mapped.length > 0);
      this.page += 1;
      loadMissingThumbs(this.context(), client, site, this.items).catch((_e: object) => {
        // 缩略图补齐失败不影响列表
      });
    } catch (e) {
      Logger.error('Search', `load failed: ${e}`);
      this.message = errorText(e as Object);
    }
    this.isRefreshing = false;
    this.isLoading = false;
  }

  /** 排除项唯一键（规则 text 本身就是完整查询词，与 `exclusionQueryOf` 的 ignored 键一致）。 */
  private exclusionKey(rule: Filter): string {
    return rule.text;
  }

  /** 排除 chip 显示文本（规则即完整查询词）。 */
  private exclusionLabel(rule: Filter): string {
    return rule.text;
  }

  @Builder
  quickSearchSheet() {
    QuickSearchSheet({
      onRun: (param: SearchParam) => {
        this.showQuickSearch = false;
        this.searchController.stopEditing();
        this.applyParam(param);
        this.submitSearch();
      }
    })
  }

  /** 标题栏底部功能区：`clock | Search | bookmark` 单行；收起态追加筛选摘要行。 */
  @Builder
  headerArea() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
          .width(TOUCH_MIN)
          .height(TOUCH_MIN)
          .padding(6)
          .onClick(() => {
            this.showQuickSearch = true;
          })
        Search({ value: this.query, placeholder: '关键词 / 标签 / 上传者', controller: this.searchController })
          .layoutWeight(1)
          .searchButton('搜索')
          .onChange((value: string) => {
            this.query = value;
          })
          .onSubmit((value: string) => {
            this.query = value;
            this.submitSearch();
          })
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
          .width(TOUCH_MIN)
          .height(TOUCH_MIN)
          .padding(4)
          .onClick(() => {
            this.saveQuick();
          })
      }
      .width('100%')
      .height(SEARCH_ROW_H)
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })

      if (!this.filtersExpanded) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize(20)
            .fontColor([$r('app.color.brand')])
            .width(TOUCH_MIN)
            .height(SUMMARY_ROW_H)
            .padding(6)
            .id('search-filter')
            .accessibilityText('筛选')
            .onClick(() => {
              this.expandFilters();
            })
          Scroll() {
            Row({ space: 6 }) {
              Repeat(this.activeChips)
                .each((ri: RepeatItem<string>) => {
                  ChipV2({
                    chipV2Options: new ChipV2Options({
                      label: new ChipV2Label({ text: ri.item, fontSize: LengthMetrics.fp(12) }),
                      size: ChipV2Size.SMALL,
                      allowClose: false,
                      onClicked: () => {
                        this.expandFilters();
                      }
                    })
                  })
                })
                .key((chip: string) => chip)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .align(Alignment.Start)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
        .width('100%')
        .height(SUMMARY_ROW_H)
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
  }

  /** `Refresh` 内置区域留空：圈由 `RefreshSpinner` 画在内容起始线（见 `ui/RefreshSpinner.ets`）。 */
  @Builder
  emptyRefreshArea() {
    Column().width('100%')
  }

  build() {
    HdsNavDestination() {
      Column() {
        Stack({ alignContent: Alignment.Top }) {
        Refresh({ refreshing: $$this.isRefreshing, builder: this.emptyRefreshArea() }) {
          List({ scroller: this.listScroller }) {
            // 顶部避让随内容滚走（标题栏 + 功能区高度）：上滑时 HDS 动态收起整块搜索区，内容顶到状态栏下。
            ListItem() {
              Column().height(this.contentTop)
            }
            if (this.filtersExpanded) {
              ListItem() {
                Column() {
                  Row() {
                    Text('FILTERS')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    SymbolGlyph($r('sys.symbol.chevron_up'))
                      .fontSize(18)
                      .fontColor([$r('app.color.text_secondary')])
                      .width(TOUCH_MIN)
                      .height(TOUCH_MIN)
                      .padding(8)
                      .accessibilityText('收起筛选')
                      .onClick(() => {
                        this.collapseFilters();
                      })
                  }
                  .width('100%')
                  .height(44)
                  .alignItems(VerticalAlign.Center)
          // 查询条件回显：把搜索框里的词拆成 chip，点 = 切换包含/排除，× = 删除。
          if (this.queryChips.length > 0) {
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              Repeat(this.queryChips)
                .each((ci: RepeatItem<string>) => {
                  ChipV2({
                    chipV2Options: new ChipV2Options({
                      label: new ChipV2Label({
                        text: ci.item,
                        activatedFontColor: ColorMetrics.resourceColor($r('app.color.danger'))
                      }),
                      size: ChipV2Size.SMALL,
                      allowClose: true,
                      activated: ci.item.startsWith('-'),
                      activatedBackgroundColor: ColorMetrics.resourceColor($r('app.color.chip_danger_bg')),
                      onClose: () => {
                        this.removeChip(ci.index);
                      },
                      onClicked: () => {
                        this.toggleChip(ci.index);
                      }
                    })
                  })
                    .margin(2)
                })
                .key((token: string) => token)
            }
            .width('100%')
            .margin({ bottom: 4 })
          }
          // 分区标题走官方 SubHeaderV2；筛选项走官方 ChipV2；每组一张卡（底 `bg_secondary`）。标签/上传者搜索同样可用。
          SubHeaderV2({
            title: new SubHeaderV2Title({ primaryTitle: 'Categories' })
          })
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Repeat(CATS)
              .each((ri: RepeatItem<CatItem>) => {
                ChipV2({
                  chipV2Options: new ChipV2Options({
                    label: new ChipV2Label({ text: ri.item.label, activatedFontColor: ColorMetrics.resourceColor($r('app.color.chip_active_text')) }),
                    size: ChipV2Size.SMALL,
                    allowClose: false,
                    activated: this.selectedBits.indexOf(ri.item.bit) >= 0,
                    activatedBackgroundColor: ColorMetrics.resourceColor($r('app.color.chip_active_bg')),
                    onClicked: () => {
                      const at: number = this.selectedBits.indexOf(ri.item.bit);
                      if (at >= 0) {
                        this.selectedBits = this.selectedBits.filter((b: number) => b !== ri.item.bit);
                      } else {
                        this.selectedBits = this.selectedBits.concat([ri.item.bit]);
                      }
                      this.searchController.stopEditing();
                      this.load(true);
                    }
                  })
                })
                  .margin(4)
              })
              .key((cat: CatItem) => cat.label)
          }
          .width('100%')
          .padding(8)
          .backgroundColor($r('app.color.bg_secondary'))
          .borderRadius(CARD_RADIUS)
          .margin({ bottom: CARD_GAP })

          SubHeaderV2({
            title: new SubHeaderV2Title({ primaryTitle: 'Search Scope' })
          })
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Repeat(SCOPES)
              .each((ri: RepeatItem<ScopeItem>) => {
                ChipV2({
                  chipV2Options: new ChipV2Options({
                    label: new ChipV2Label({ text: ri.item.label, activatedFontColor: ColorMetrics.resourceColor($r('app.color.chip_active_text')) }),
                    size: ChipV2Size.SMALL,
                    allowClose: false,
                    activated: this.scopes.indexOf(ri.item.key) >= 0,
                    activatedBackgroundColor: ColorMetrics.resourceColor($r('app.color.chip_active_bg')),
                    onClicked: () => {
                      if (this.scopes.indexOf(ri.item.key) >= 0) {
                        this.scopes = this.scopes.filter((k: string) => k !== ri.item.key);
                      } else {
                        this.scopes = this.scopes.concat([ri.item.key]);
                      }
                      this.searchController.stopEditing();
                      this.load(true);
                    }
                  })
                })
                  .margin(4)
              })
              .key((scope: ScopeItem) => scope.key)
          }
          .width('100%')
          .padding(8)
          .backgroundColor($r('app.color.bg_secondary'))
          .borderRadius(CARD_RADIUS)
          .margin({ bottom: CARD_GAP })

          SubHeaderV2({
            title: new SubHeaderV2Title({ primaryTitle: 'Language' })
          })
          // 单选 → 与上下卡片同宽同圆角（不用 `HdsListItemCard`：它自带 16 外缩，套在已有 16 的栅格里会变成 32）。
          Row({ space: 8 }) {
            Text('Only show')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Select(langSelectOptions())
              .selected(this.selectedLang.length > 0 ? SEARCH_LANGUAGES.indexOf(this.selectedLang) + 1 : 0)
              .value(this.selectedLang.length > 0 ? this.selectedLang : LANG_ANY)
              .font({ size: 14 })
              .fontColor($r('app.color.brand'))
              .backgroundColor(Color.Transparent)
              .onSelect((index: number) => {
                const next: string = index === 0 ? '' : SEARCH_LANGUAGES[index - 1];
                if (next === this.selectedLang) {
                  return;
                }
                this.selectedLang = next;
                this.searchController.stopEditing();
                this.load(true);
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.bg_secondary'))
          .borderRadius(CARD_RADIUS)
          .margin({ bottom: CARD_GAP })

          if (this.activeRules.length > 0) {
            SubHeaderV2({
              title: new SubHeaderV2Title({ primaryTitle: 'Exclusions' })
            })
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              Repeat(this.activeRules)
                .each((ri: RepeatItem<Filter>) => {
                  ChipV2({
                    chipV2Options: new ChipV2Options({
                      label: new ChipV2Label({
                        text: this.exclusionLabel(ri.item),
                        activatedFontColor: ColorMetrics.resourceColor($r('app.color.danger'))
                      }),
                      size: ChipV2Size.SMALL,
                      allowClose: false,
                      // 未忽略 = 生效排除（danger 色调）；忽略 = 普通芯片。
                      activated: this.ignoredExclusions.indexOf(this.exclusionKey(ri.item)) < 0,
                      activatedBackgroundColor: ColorMetrics.resourceColor($r('app.color.chip_danger_bg')),
                      onClicked: () => {
                        const key: string = this.exclusionKey(ri.item);
                        if (this.ignoredExclusions.indexOf(key) >= 0) {
                          this.ignoredExclusions =
                            this.ignoredExclusions.filter((k: string) => k !== key);
                        } else {
                          this.ignoredExclusions = this.ignoredExclusions.concat([key]);
                        }
                        this.searchController.stopEditing();
                        this.load(true);
                      }
                    })
                  })
                    .margin(4)
                })
                .key((rule: Filter) => `${rule.id}`)
            }
            .width('100%')
            .padding(8)
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(CARD_RADIUS)
            .margin({ bottom: 4 })
            Text('点一下可临时忽略这条规则（只影响本次搜索）')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ bottom: CARD_GAP })
          }

          SubHeaderV2({
            title: new SubHeaderV2Title({ primaryTitle: 'Minimum Rating' })
          })
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Repeat(STARS)
              .each((ri: RepeatItem<number>) => {
                ChipV2({
                  chipV2Options: new ChipV2Options({
                    label: new ChipV2Label({ text: `${ri.item}+`, activatedFontColor: ColorMetrics.resourceColor($r('app.color.chip_active_text')) }),
                    size: ChipV2Size.SMALL,
                    allowClose: false,
                    activated: this.minRating === ri.item,
                    activatedBackgroundColor: ColorMetrics.resourceColor($r('app.color.chip_active_bg')),
                    onClicked: () => {
                      this.minRating = this.minRating === ri.item ? -1 : ri.item;
                      this.searchController.stopEditing();
                      this.load(true);
                    }
                  })
                })
                  .margin(4)
              })
              .key((star: number) => `${star}`)
          }
          .width('100%')
          .padding(8)
          .backgroundColor($r('app.color.bg_secondary'))
          .borderRadius(CARD_RADIUS)
          .margin({ bottom: CARD_GAP })

          // 高级选项：默认折叠（低频）。展开后是 有种子 / 忽略站点过滤 / 页数区间。
          SubHeaderV2({
            title: new SubHeaderV2Title({ primaryTitle: 'Advanced' })
          })
          Row() {
            Text('More options')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Blank()
            SymbolGlyph($r(this.advancedExpanded ? 'sys.symbol.chevron_up' : 'sys.symbol.chevron_down'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
              .padding(12)
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.bg_secondary'))
          .borderRadius(CARD_RADIUS)
          .margin({ bottom: CARD_GAP })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.advancedExpanded = !this.advancedExpanded;
          })
          if (this.advancedExpanded) {
            Column({ space: 8 }) {
              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                ChipV2({
                  chipV2Options: new ChipV2Options({
                    label: new ChipV2Label({
                      text: '有种子',
                      activatedFontColor: ColorMetrics.resourceColor($r('app.color.chip_active_text'))
                    }),
                    size: ChipV2Size.SMALL,
                    allowClose: false,
                    activated: this.onlyTorrents,
                    activatedBackgroundColor: ColorMetrics.resourceColor($r('app.color.chip_active_bg')),
                    onClicked: () => {
                      this.onlyTorrents = !this.onlyTorrents;
                      this.searchController.stopEditing();
                      this.load(true);
                    }
                  })
                })
                  .margin(4)
                ChipV2({
                  chipV2Options: new ChipV2Options({
                    label: new ChipV2Label({
                      text: '忽略站点过滤',
                      activatedFontColor: ColorMetrics.resourceColor($r('app.color.chip_active_text'))
                    }),
                    size: ChipV2Size.SMALL,
                    allowClose: false,
                    activated: this.ignoreFilters,
                    activatedBackgroundColor: ColorMetrics.resourceColor($r('app.color.chip_active_bg')),
                    onClicked: () => {
                      this.ignoreFilters = !this.ignoreFilters;
                      this.searchController.stopEditing();
                      this.load(true);
                    }
                  })
                })
                  .margin(4)
              }
              .width('100%')
              Row({ space: 8 }) {
                Text('页数')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                TextInput({ text: this.pageFromText, placeholder: '从' })
                  .type(InputType.Number)
                  .layoutWeight(1)
                  .height(36)
                  .onChange((value: string) => { this.pageFromText = value; })
                  .onSubmit(() => { this.load(true); })
                Text('–')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                TextInput({ text: this.pageToText, placeholder: '到' })
                  .type(InputType.Number)
                  .layoutWeight(1)
                  .height(36)
                  .onChange((value: string) => { this.pageToText = value; })
                  .onSubmit(() => { this.load(true); })
              }
              .width('100%')
              Text('页数区间过窄（如 1000 到 10）会返回 0 条；留空 = 不限。')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding(8)
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(CARD_RADIUS)
            .margin({ bottom: CARD_GAP })
          }
                }
                .width('100%')
                .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
                // 官方转场：展开/收起同时淡入淡出（与 animateTo 配合，非自绘）。
                .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
              }
            }

            LazyForEach(this.dataSource, (item: GalleryRowItem) => {
              ListItem() {
                GalleryRow({ item: item })
                  .onClick(() => {
                    pushGalleryDetail(this.getUIContext(), this.pageStack, item);
                  })
              }
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING, bottom: CARD_GAP })
            }, (item: GalleryRowItem) => `${item.gid}`)

            if (this.message.length > 0) {
              ListItem() {
                Row({ space: 8 }) {
                  if (this.message.endsWith('…')) {
                    LoadingProgress().width(32).height(32)
                  } else {
                    Text(this.message)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding(12)
              }
            }
          }
          .width('100%')
          .height('100%')
          .cachedCount(4)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
        .onRefreshing(() => { this.searchController.stopEditing(); this.load(true); })
        .onOffsetChange((v: number) => { this.pullOffset = v; })
        .onStateChange((s: RefreshStatus) => {
          if (s === RefreshStatus.Done) {
            this.pullOffset = 0;
          }
        })
        RefreshSpinner({
          pullOffset: this.pullOffset,
          isRefreshing: this.isRefreshing,
          top: this.contentTop + 4
        })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_primary'))
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      style: navTitleBarStyle(),
      content: {
        title: { mainTitle: this.pageTitle },
        bottomBuilder: { builder: () => { this.headerArea() }, height: this.headerHeight }
      }
    })
    // 上滑收起标题 + 搜索功能区（含收起态摘要），下滑复原：结果页只留内容。
    .bindToScrollable([this.listScroller])
    .dynamicHideTitleBar({ hideTitleArea: true, hideBottomBuilder: true, mode: HideMode.SCROLL_UP })
    .bindSheet($$this.showQuickSearch, this.quickSearchSheet(), {
      title: { title: '快速搜索' },
      // 内容是 List（无固有高度，`FIT_CONTENT` 量不出来）：半屏起步，可上拖到全屏。
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      systemMaterial: SHEET_MATERIAL
    })
    .onAppear(() => {
      if (this.kind === 'keyword') {
        this.reloadRules();
      }
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
      const param: SearchParam | undefined = ctx.pathInfo.param as SearchParam | undefined;
      if (param !== undefined) {
        this.applyParam(param);
        this.load(true);
      }
    })
  }
}
