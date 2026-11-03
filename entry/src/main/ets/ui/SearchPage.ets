import { common } from '@kit.AbilityKit';
import { AppStorageV2, PersistenceV2, promptAction, ChipV2, ChipV2Label, ChipV2Options, ChipV2Size, ColorMetrics, LengthMetrics, SubHeaderV2, SubHeaderV2Title, SymbolGlyphModifier } from '@kit.ArkUI';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { GalleryInfo } from '../model/GalleryInfo';
import { GalleryListFeed } from './GalleryListFeed';
import { GalleryListPage } from '../parser/GalleryListParser';
import { SearchKind, SearchParam } from '../model/SearchParam';
import { Logger } from '../common/Logger';
import { errorText } from '../common/ErrorText';
import { AppSettings } from '../state/AppSettings';
import { WindowState } from '../state/WindowState';
import { HdsNavDestination, HideMode, HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { GalleryRow, GalleryRowItem, loadMissingThumbs, pushGalleryDetail } from './GalleryRow';
import { fCatsMask, excludedFromSelected, encodeAdvance, ALL_CATS, languageQueryOf, SEARCH_LANGUAGES, exclusionQueryOf, SearchFilters } from '../search/SearchQuery';
import { shouldSuggest, trailingToken, TagToken } from '../search/TagInput';
import { appendDraft, joinQueryText, splitQueryTokens, suggestionChip } from '../search/QuerySegments';
import { TagCandidate } from '../tagdb/TagCandidate';
import { TagDb } from '../tagdb/TagDb';
import { TagSuggestionPanel } from './TagSuggestionPanel';
import { FilterDao } from '../db/dao/FilterDao';
import { DbHelper } from '../db/DbHelper';
import { Filter } from '../model/Filter';
import { PagedDataSource, PREFETCH_TAIL, shouldFetchMore } from '../common/PagedList';
import { QuickSearchDao } from '../db/dao/QuickSearchDao';
import { QuickSearch } from '../model/QuickSearch';
import { hasSavedKeyword } from '../search/QuickSearchQuery';
import { QuickSearchSheet } from './QuickSearchSheet';
import { CARD_GAP, CARD_RADIUS, PAGE_PADDING, TOUCH_MIN } from './Materials';
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
/** 搜索输入框的组件 id（`＋` 之后要把焦点还给它）。 */
const SEARCH_FIELD_ID: string = 'search-draft';
/** 收起态筛选摘要行高度（vp）。 */
const SUMMARY_ROW_H: number = 40;

/** 中文联想防抖（ms）：中文输入法上屏一个字的间隔量级；再短就会每敲一下全表扫一遍。 */
const SUGGEST_DEBOUNCE_MS: number = 150;
/** 一次取的候选数：面板内部可滚动，多取一些让「第 7 条以后」也能在面板里翻到（排序已在 `searchTags` 内完成）。 */
const SUGGEST_FETCH_LIMIT: number = 20;

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
 * 搜索页（关键词 / 标签两态经 `SearchParam.kind` 进入；上传者已折叠成 `uploader:"…"` 普通条件）。
 * 结果页与首页同构，复用 `GalleryListParser`。状态与首页隔离：独立 `page`/`items`。
 *
 * 查询模型：输入框只放**草稿**，回车 / ＋ / 点候选才把草稿变成一条 chip（`segments`）；
 * 发出去的 `f_search` 由 `queryText`（条件 + 草稿）拼成，不再把整串塞回输入框。
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
  /**
   * 已确认的查询条件（按加入顺序拼进 `f_search`）。chip 行的唯一真源。
   * 只整体替换、不原地改：`@Local` 的数组刷新靠引用变化。
   */
  @Local segments: string[] = [];
  /**
   * 输入框里的草稿：只放「还在输入」的部分。
   * 空格就是空格（英文 tag 自带空格），回车 / 点「＋」/ 点候选才转成 chip。
   */
  @Local draft: string = '';
  /** chip 行实测高度（vp；无 chip 时不渲染 → 0）。喂给 `headerHeight`，让内容避让自动跟随。 */
  @Local chipsHeight: number = 0;
  @Local kind: SearchKind = 'keyword';
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
  private isLoading: boolean = false;
  /** 结果列表滚动器（折叠/展开筛选时回顶用；不再有吸顶 header）。 */
  private listScroller: Scroller = new Scroller();
  /** 分页状态唯一持有者（items / 下一页游标 / 已访问 URL）。 */
  private feed: GalleryListFeed = new GalleryListFeed(async (url: string): Promise<GalleryListPage> => {
    return this.fetchPage(url);
  });
  /** 懒加载数据源（只负责 items + hasMore；预取由页面在滚动到底时显式触发）。 */
  private dataSource: PagedDataSource<GalleryRowItem> =
    new PagedDataSource<GalleryRowItem>(() => {
      return this.isLoading;
    });

  private async fetchPage(url: string): Promise<GalleryListPage> {
    const cookies: CookieStore = new CookieStore();
    await cookies.init(this.context());
    const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
    return client.getGalleryList(this.settings.site, url, this.settings.thumbSize);
  }
  private pageStack: NavPathStack | undefined = undefined;
  /** 搜索框控制器（官方收键盘手段：`SearchController.stopEditing()`；见 `search.d.ts:74`）。 */
  private searchController: SearchController = new SearchController();
  /** 中文联想候选（`TagDb.search`；空 = 无候选，面板不渲染，避免空卡片）。 */
  @Local suggestions: TagCandidate[] = [];
  /** 产生这批候选时用的片段：入列前用它核对草稿是否还是同一串（期间用户可能已改输入）。 */
  @Local suggestToken: TagToken | undefined = undefined;
  /** 联想面板是否展开（`if` 的条件必须是可观察状态，见 `ui/AGENTS.md` #19）。 */
  @Local suggestionsOpen: boolean = false;
  /** 联想防抖定时器（`-1` = 没有待执行的回调）。 */
  private suggestTimer: number = -1;

  /**
   * 页面被 pop：清掉待发的联想回调。
   * 否则回调会在已销毁的组件上写 `@Local`，并白跑一次 4.4 万条的全表扫描。
   */
  aboutToDisappear(): void {
    this.cancelSuggestTimer();
  }

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  /** 标题栏底部功能区高度：单行搜索 + chip 行（实测）+ 收起态摘要行。 */
  @Computed get headerHeight(): number {
    // chips 画在页面内容区（见 `chipsRow`），不再进标题栏高度：
    // 标题栏的 bottomBuilder 里，超出首屏高度的子节点拿不到点击（实测 chip 点不动）。
    return SEARCH_ROW_H + (this.filtersExpanded ? 0 : SUMMARY_ROW_H);
  }

  /**
   * 发给站点的 `f_search` 主体 = 已确认条件 + 非空草稿。
   * 上传者（`uploader:"…"`）与标签（`ns:"tag$"`）都只是普通条件，这里不再按模式改写。
   */
  @Computed get queryText(): string {
    return joinQueryText(this.segments, this.draft);
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

  /** 提交搜索（键盘回车 / 蓝「搜索」/ 快搜运行）：收联想 + 收键盘 + 收筛选 + 回顶，再重搜。 */
  private submitSearch(): void {
    this.showQuickSearch = false;
    this.closeSuggestions();
    this.searchController.stopEditing();
    if (this.filtersExpanded) {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
        this.filtersExpanded = false;
        this.listScroller.scrollToIndex(0);
      });
    }
    this.load(true);
  }

  /**
   * 输入变化 → 防抖 150 ms 再查标签库。
   * 每次输入先清旧定时器：中文输入法逐字上屏时会连发 `onChange`，
   * 每次都全表扫 4.4 万条名字会拖慢输入。
   */
  private scheduleSuggest(value: string): void {
    this.cancelSuggestTimer();
    this.suggestTimer = setTimeout(() => {
      this.runSuggest(value);
    }, SUGGEST_DEBOUNCE_MS);
  }

  private cancelSuggestTimer(): void {
    if (this.suggestTimer >= 0) {
      clearTimeout(this.suggestTimer);
      this.suggestTimer = -1;
    }
  }

  /**
   * 防抖到点：只在「草稿最后一个片段含中日文」时给候选。
   * 只看草稿（不再解析整段查询）：已确认条件早已是 `ns:"tag$"` 正规语法，再拿去联想只会匹到自己。
   * 回调里不碰 `getUIContext()`（`ui/AGENTS.md` #26：脱离 UI 上下文会抛错）。
   */
  private runSuggest(value: string): void {
    this.suggestTimer = -1;
    // 等待期间用户又改了输入：这次结果已经过期，丢弃（否则会把上一个词的候选闪回面板）。
    if (value !== this.draft) {
      return;
    }
    const token: TagToken | undefined = trailingToken(value);
    if (token === undefined || !shouldSuggest(token.word)) {
      this.closeSuggestions();
      return;
    }
    // 标签库未就绪 / 翻译开关关闭时 `TagDb.search` 返回 `[]` → 保持关闭，不显示空卡片。
    const found: TagCandidate[] = TagDb.search(token.word, SUGGEST_FETCH_LIMIT);
    if (found.length === 0) {
      this.closeSuggestions();
      return;
    }
    this.suggestions = found;
    this.suggestToken = token;
    this.suggestionsOpen = true;
  }

  private closeSuggestions(): void {
    this.cancelSuggestTimer();
    this.suggestionsOpen = false;
    this.suggestions = [];
    this.suggestToken = undefined;
  }

  /**
   * 选中候选：把 `ns:"tag$"` 精确语法作为一条 chip 入列，并保留草稿前导的 `-`/`~`。
   * 草稿里只有「正在输入」的一段，所以不需要再算替换区间——但要先核对草稿还是产生候选时那串：
   * 候选与 `onChange` 之间隔着 150 ms 防抖，用户可能已经改过输入（此时按旧候选入列就是错的）。
   * 不自动搜索——用户常常还要接着拼第二个标签；草稿清空、光标回到开头，连续输入不中断。
   */
  private pickSuggestion(ns: string, tag: string): void {
    const token: TagToken | undefined = this.suggestToken;
    if (token === undefined) {
      this.closeSuggestions();
      return;
    }
    if (this.draft.substring(token.start, token.end) !== token.word) {
      this.closeSuggestions();
      return;
    }
    const chip: string = suggestionChip(this.draft, ns, tag);
    // 草稿里排在当前片段前面的内容也要留住：用户可能一口气敲了「foo 巨乳」再点候选，
    // 直接清空草稿会把 `foo` 悄悄丢了。纯前缀（`-`/`~`）不算内容，它已经并进 chip。
    const head: string = this.draft.substring(0, token.start).trim();
    const kept: string[] = head.length === 0 || head === '-' || head === '~' ? [] : splitQueryTokens(head);
    kept.push(chip);
    this.closeSuggestions();
    this.segments = this.segments.concat(kept);
    this.draft = '';
    this.searchController.caretPosition(0);
  }

  /**
   * 草稿 → chip（回车 / 「＋」共用）。原样入列，只 trim 首尾：
   * 用户可能正在手写 `uploader:"名字"` 这类条件，替它规范化反而会改坏。
   */
  private commitDraft(): void {
    const next: string[] = appendDraft(this.segments, this.draft);
    if (next === this.segments) {
      return;
    }
    this.closeSuggestions();
    this.segments = next;
    this.draft = '';
    this.searchController.caretPosition(0);
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

  /** 存为快速搜索；名取当前查询（`f_search` 主体，URL 也只用它，不再按模式改写）。 */
  private async saveQuick(): Promise<void> {
    const keyword: string = this.queryText;
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
        category: fCatsMask(excludedFromSelected(this.selectedBits, ALL_CATS)),
        keyword: keyword,
        language: this.selectedLang,
        advanceSearch: encodeAdvance(this.scopes, this.langFilter),
        minRating: this.minRating, time: Date.now()
      });
      promptAction.showToast({ message: '已存到快搜' });
    } catch (e) {
      Logger.error('QSearch', `save failed: ${e}`);
      promptAction.showToast({ message: '保存失败，请重试' });
    }
  }

  /** 路由参数（含快搜运行带条件）→ 本页状态；缺字段回退默认。 */
  private applyParam(param: SearchParam): void {
    // 换了一套查询条件：旧候选与它的片段区间不再对应新草稿，必须一起收起。
    this.closeSuggestions();
    // 入口给的是完整查询串（标签/上传者都已是 `ns:"tag$"` / `uploader:"…"` 正规语法）：
    // 按引号安全切词回填成 chips，输入框留空——用户接下来敲的是**追加**条件。
    this.segments = splitQueryTokens(param.query);
    this.draft = '';
    if (this.segments.length === 0) {
      // 这块不再渲染，`onAreaChange` 不会再来 → 高度必须手动归零，否则内容顶部会多留一段空白。
      this.chipsHeight = 0;
    }
    this.kind = param.kind;
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

  /** 点 chip：包含 ↔ 排除（改 `segments` 后立即重搜）。 */
  private toggleChip(index: number): void {
    if (index < 0 || index >= this.segments.length) {
      return;
    }
    const next: string[] = this.segments.slice();
    const token: string = next[index];
    next[index] = token.startsWith('-') ? token.substring(1) : `-${token}`;
    // 条件变了：候选是按旧草稿算的，留着会按过期区间入列。
    this.closeSuggestions();
    this.segments = next;
    this.load(true);
  }

  private removeChip(index: number): void {
    if (index < 0 || index >= this.segments.length) {
      return;
    }
    const next: string[] = this.segments.slice();
    next.splice(index, 1);
    this.closeSuggestions();
    if (next.length === 0) {
      // 最后一条 chip 删掉后 chip 行不再渲染：`onAreaChange` 不会再来，高度必须在这里归零。
      this.chipsHeight = 0;
    }
    this.segments = next;
    this.load(true);
  }

  private buildUrl(site: EhSite): string {
    // 三种入口（关键词 / 上传者 / 标签）现在都只是普通条件：上传者写 `uploader:"…"`、
    // 标签写 `ns:"tag$"`，由入列时的文字决定，这里不再按模式改写（再包一层会得到
    // `parody:""blue archive$"` 这种坏串）。
    let keyword: string = this.queryText;
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
    return EhUrl.search(site, keyword, 0, fCatsMask(bits), filters);
  }

  /** 排除规则重读（每次搜索自动拼 `-…` 查询条件；不再本地过滤列表）。 */
  private async reloadRules(): Promise<void> {
    // 从详情页点进来的单标签查询不套屏蔽规则（那是"看这个标签"的精确入口）；
    // 上传者已折叠成普通关键词查询，不再单列分支。
    if (this.kind === 'tag') {
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
    if (this.kind === 'keyword' && this.queryText.length === 0 &&
      this.selectedLang.length === 0 && exclFrag.length === 0) {
      this.message = '';
      this.isRefreshing = false;
      return;
    }
    this.isLoading = true;
    try {
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      this.message = '搜索中…';
      // 后续页面一律用站点给的 next（搜索是 `?next=<gid>` 游标）；这里只构造第一页。
      await this.feed.load(this.buildUrl(site), refresh);
      this.items = this.feed.items;
      this.message = this.items.length === 0 ? '没有找到相关画廊' : '';
      this.dataSource.setItems(this.items, this.feed.hasMore);
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

  /**
   * 标题栏右侧菜单项（官方页面级动作槽位）。
   *
   * 图标必须走 `SymbolGlyphModifier`：`IconType` 的 `ResourceStr` 分支是**图片**资源，符号字体（`sys.symbol.*`）
   * 在里面画不出来；`SymbolGlyphModifier(src)` 才是符号的正确入口。
   * 颜色显式给 `text_primary`：HDS 默认着色不与 `navTitleBarStyle()` 的标题色同源，深色下会看不见。
   */
  private menuItem(symbol: Resource, label: string, action: () => void): HdsNavigationMenuItemOptions {
    const icon: SymbolGlyphModifier = new SymbolGlyphModifier(symbol);
    icon.fontColor([$r('app.color.text_primary')]);
    return { content: { icon: icon, label: label, action: action } };
  }

  /** 快速搜索（存过的条件）与「存为快搜」：低频页面级动作，从搜索行挪到标题栏，把行宽还给输入框。 */
  private titleMenus(): HdsNavigationMenuItemOptions[] {
    return [
      this.menuItem($r('sys.symbol.clock'), '快速搜索', () => {
        this.showQuickSearch = true;
      }),
      this.menuItem($r('sys.symbol.bookmark'), '保存为快速搜索', () => {
        this.saveQuick();
      })
    ];
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

  /**
   * 标题栏底部功能区：`Search | ＋` 单行 + 已确认条件 chips；收起态追加筛选摘要行。
   *
   * 行内只留输入框与「＋」：三个 44vp 热区 + 3 个 8vp 间距会吃掉四成行宽（360vp 屏上输入区只剩 ~70vp，
   * 占位文字被截成「输…」）。`clock`（快速搜索）与 `bookmark`（存为快搜）是页面级动作，
   * 走标题栏官方菜单槽位（`titleBar.content.menu`），图形、热区与材质由 HDS 提供。
   */
  @Builder
  headerArea() {
    Column() {
      Row({ space: 4 }) {
        Search({ value: this.draft, placeholder: '关键词或标签', controller: this.searchController })
          .id(SEARCH_FIELD_ID)
          .layoutWeight(1)
          .searchButton('搜索')
          .onChange((value: string) => {
            // 输入框只承载草稿：空格就是空格（英文 tag 自带空格），不做「空格成词」。
            this.draft = value;
            // 标签联想：只看草稿，中英文走同一条路；太短的片段（拉丁 <2 字符）在 `runSuggest` 里被挡掉。
            this.scheduleSuggest(value);
          })
          .onSubmit((value: string) => {
            // 回车 = 先把草稿变成 chip，再搜（搜的是同一串条件，只是输入框腾空好接着拼）。
            this.draft = value;
            this.commitDraft();
            this.submitSearch();
          })
        // 「＋」：草稿成词（与回车等价，但留着键盘）。草稿为空时是空操作。
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
          .width(TOUCH_MIN)
          .height(TOUCH_MIN)
          .padding(4)
          .accessibilityText('把草稿变成条件')
          .onClick(() => {
            if (this.draft.trim().length === 0) {
              return;
            }
            this.commitDraft();
            // 点图标会把焦点从 Search 拿走：补回来，用户接着输入下一个条件。
            this.getUIContext().getFocusController().requestFocus(SEARCH_FIELD_ID);
          })
      }
      .width('100%')
      .height(SEARCH_ROW_H)
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })


      if (!this.filtersExpanded) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize(20)
            .fontColor([$r('sys.color.brand')])
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

  /**
   * 已确认条件（chips）：常驻在内容起始线、无限换行（不设行数上限、不横向滚动）。
   *
   * 为什么画在页面 `Stack` 而不是标题栏 `bottomBuilder`：实测那里只有首行（`SEARCH_ROW_H`）能收到点击，
   * 超出的 chip 既不能切换包含/排除、也点不到 ×（渲染正常，命中区没有）。这里跟联想浮层同一层，命中正常。
   * 高度实测回写 `chipsHeight`：列表顶部占位与联想浮层位置都靠它跟随，而不是按「每行 32vp」估。
   */
  @Builder
  chipsRow() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Repeat(this.segments)
          .each((ri: RepeatItem<string>) => {
            // 自定义 chip（不用 `ChipV2`）：官方组件在这里的关闭按钮命中不到（真机实证：点本体能切换、
            // 点 × 没反应）。Row + 图标两个命中区都正常；它是内容控件，不是"自绘装饰遮罩"。
            Row({ space: 6 }) {
              Text(ri.item)
                .fontSize(12)
                .fontColor(ri.item.startsWith('-') ? $r('app.color.danger') : $r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(12)
                .fontColor([ri.item.startsWith('-') ? $r('app.color.danger') : $r('app.color.text_secondary')])
                .onClick(() => {
                  this.removeChip(ri.index);
                })
            }
            .padding({ left: 10, right: 8, top: 6, bottom: 6 })
            .backgroundColor(ri.item.startsWith('-')
              ? $r('app.color.chip_danger_bg')
              : $r('app.color.bg_secondary'))
            .borderRadius(16)
            .onClick(() => {
              this.toggleChip(ri.index);
            })
            .margin(3)
          })
          // key 必须带内容：只按 index 的话，`-` 前缀切换后 key 不变，`Repeat` 会复用旧节点、
          // 不重建，表现为"点了没反应"（真机实证：日志已进 `toggleChip`，色却不变）。
          .key((token: string, index: number) => `${index}:${token}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 4, bottom: 6 })
    // 不再 `.offset` / 背景色：它现在是列表里的一块正常内容（`.offset` 会变成固定浮层）。
    .onAreaChange((_old: Area, now: Area) => {
      const height: Length = now.height;
      if (typeof height !== 'number' || height <= 0) {
        return;
      }
      // 只在变化时写：避免「测高 → 重布局 → 又测出同一个值」的回声。
      if (height !== this.chipsHeight) {
        this.chipsHeight = height;
      }
    })
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
            // 已确认条件：列表里的第一块内容，跟着列表一起滚走。
            // 早先画在页面 `Stack` 里（`.offset` 固定定位），下滑时会「悬浮」盖住 Categories 卡片（真机截图踩到）。
            if (this.segments.length > 0) {
              ListItem() {
                this.chipsRow()
              }
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
          // 分区标题走官方 SubHeaderV2；筛选项走官方 ChipV2；每组一张卡（底 `bg_secondary`）。标签/上传者搜索同样可用。
          SubHeaderV2({
            title: new SubHeaderV2Title({ primaryTitle: 'Categories' })
          })
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Repeat(CATS)
              .each((ri: RepeatItem<CatItem>) => {
                ChipV2({
                  chipV2Options: new ChipV2Options({
                    label: new ChipV2Label({ text: ri.item.label }),
                    size: ChipV2Size.SMALL,
                    allowClose: false,
                    activated: this.selectedBits.indexOf(ri.item.bit) >= 0,
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
                    label: new ChipV2Label({ text: ri.item.label }),
                    size: ChipV2Size.SMALL,
                    allowClose: false,
                    activated: this.scopes.indexOf(ri.item.key) >= 0,
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
              .fontColor($r('sys.color.brand'))
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
                    label: new ChipV2Label({ text: `${ri.item}+` }),
                    size: ChipV2Size.SMALL,
                    allowClose: false,
                    activated: this.minRating === ri.item,
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
                      text: '有种子'
                    }),
                    size: ChipV2Size.SMALL,
                    allowClose: false,
                    activated: this.onlyTorrents,
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
                      text: '忽略站点过滤'
                    }),
                    size: ChipV2Size.SMALL,
                    allowClose: false,
                    activated: this.ignoreFilters,
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
          // 预取：滚到尾部窗口就问一次（`getData` 不再有副作用）。
          .onScrollIndex((_start: number, end: number) => {
            if (shouldFetchMore(this.items.length, end + PREFETCH_TAIL, this.feed.hasMore, this.isLoading)) {
              this.load(false);
            }
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
          // 上滑即收起联想：整块搜索区（含输入框）会随标题栏一起隐藏，面板留着就成了无主浮层。
          .onScrollStart(() => {
            this.closeSuggestions();
          })
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
          top: this.contentTop + this.chipsHeight + 4
        })
        // 中文联想面板：同一 `Stack` 内、chips 之下，只占自身高度（不铺满 → 不吞下层手势，#21）。
        // **不能**塞进标题栏 `bottomBuilder`：那里的高度是固定的 `headerHeight`，同时喂给 `contentTop`
        // 与刷新圈位置，撑大它会一次算错三处布局（#38 / #51）。
        if (this.suggestionsOpen) {
          Column() {
            TagSuggestionPanel({
              items: this.suggestions,
              onPick: (ns: string, tag: string) => {
                this.pickSuggestion(ns, tag);
              }
            })
          }
          .width('100%')
          .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
          .offset({ top: this.contentTop + this.chipsHeight })
          .transition(TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.EaseOut }))
        }
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
        title: { mainTitle: '搜索' },
        menu: { value: this.titleMenus() },
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
