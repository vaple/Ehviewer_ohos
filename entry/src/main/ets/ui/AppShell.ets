import { AppStorageV2, CapsuleSegmentButtonV2, LengthMetrics, PersistenceV2, SegmentButtonV2ItemOptions, SegmentButtonV2Items, SymbolGlyphModifier, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { BlurStrategy, HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController, HdsNavigationMenuContentOptions, ScrollEffectType } from '@kit.UIDesignKit';
import { DiscoverListPage } from './DiscoverListPage';
import { TopListPage } from './TopListPage';
import { MyPage } from './MyPage';
import { GalleryDetailPage } from './GalleryDetailPage';
import { CommentsPage } from './CommentsPage';
import { FavoritesPage } from './FavoritesPage';
import { HistoryPage } from './HistoryPage';
import { BlockListPage } from './BlockListPage';
import { SearchPage } from './SearchPage';
import { ReaderPage } from './ReaderPage';
import { SettingsPage } from './SettingsPage';
import { DownloadsPage } from './DownloadsPage';
import { HDS_MATERIAL, PAGE_PADDING } from './Materials';
import { RANK_CHIPS_H, TITLE_BAR_H } from './NavStyle';
import { RANK_RANGES, RankState } from '../state/RankState';
import { SessionState } from '../state/SessionState';
import { WindowState } from '../state/WindowState';
import { AppSettings, displayModeToColorMode } from '../state/AppSettings';
import { CookieStore } from '../network/CookieStore';
import { downloadManager } from '../service/DownloadManager';
import { Logger } from '../common/Logger';

const TAB_TITLES: string[] = ['热门', '订阅', '排行', '我的'];

/**
 * 应用主框架：`HdsNavigation` 路由根 + `HdsTabs` 底部四页签（热门/订阅/排行/我的）。
 * push 页（详情/阅读/搜索/收藏/历史/设置…）覆盖 tabs 全屏。
 * tab 根页经 `@Param pageStack` 拿栈（`TabContent` 内无 `NavDestination` 上下文）。
 */
@ComponentV2
export struct AppShell {
  @Local pageStack: NavPathStack = new NavPathStack();
  @Local currentTab: number = 0;
  /** 系统安全区（状态栏 / 手势条，vp；运行时读，不写死机型值）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  private tabsController: HdsTabsController = new HdsTabsController();
  /** 上一次记录的安全区日志（只在数值变化时打，避免 `onAreaChange` 刷屏）。 */
  private lastSafeAreaLog: string = '';
  /** 四 tab 独立滚动器（标题栏渐进模糊联动用；只绑当前 tab，互不干扰）。 */
  private scrollerHot: Scroller = new Scroller();
  private scrollerSub: Scroller = new Scroller();
  private scrollerRank: Scroller = new Scroller();
  private scrollerMine: Scroller = new Scroller();
  /** 应用设置（显示模式解析深浅用；与 `applyDisplayMode` 同一全局连接）。 */
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  /** 登录态（内存态；`SettingsPage` 写 Cookie 后置位，`MyPage` 读取展示）。 */
  private session: SessionState = AppStorageV2.connect(SessionState, () => new SessionState())!;
  /** 排行档位（标题栏胶囊写、`TopListPage` 监听重载）。 */
  private rankState: RankState = AppStorageV2.connect(RankState, () => new RankState())!;

  /** 冷启动同步登录态（Cookie 本体已落盘；杀进程重启后内存态归零，在此重算）。 */
  private async refreshLoginState(): Promise<void> {
    try {
      const ctx: common.Context =
        this.getUIContext().getHostContext() as common.Context;
      const store: CookieStore = new CookieStore();
      await store.init(ctx);
      this.session.loggedIn = store.has('ipb_member_id');
    } catch (e) {
      // 读不到就保持原态，不挡启动
    }
  }

  /** 初始化下载队列（续传上次未完成的任务；失败只记日志，不挡启动）。 */
  private async initDownloads(): Promise<void> {
    try {
      const ctx: common.Context =
        this.getUIContext().getHostContext() as common.Context;
      await downloadManager.init(ctx);
    } catch (e) {
      Logger.error('Download', `manager init failed: ${e}`);
    }
  }

  /**
   * 读取系统避让区（状态栏 / 挖孔 / 手势条），标题栏与内容避让用；读不到保持 0（不挡启动）。
   *
   * **顶部取 `TYPE_SYSTEM` 与 `TYPE_CUTOUT` 的较大值**：刘海/挖孔机型（如顶部大药丸）的挖孔
   * 会低于状态栏高度，只按状态栏避让会让内容（如下拉刷新圈）钻到挖孔下面被挡住。
   */
  private async applySafeArea(): Promise<void> {
    try {
      const ctx: common.Context =
        this.getUIContext().getHostContext() as common.Context;
      const win: window.Window = await window.getLastWindow(ctx);
      // 同步接口（`@ohos.window.d.ts`：`getWindowAvoidArea(type): AvoidArea`），不能 await。
      const sys: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutout: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const bottom: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topPx: number = Math.max(sys.topRect.height, cutout.topRect.height);
      if (topPx > 0) {
        this.windowState.safeTop = px2vp(topPx);
      }
      if (bottom.bottomRect.height > 0) {
        this.windowState.safeBottom = px2vp(bottom.bottomRect.height);
      }
      // 只在数值变化时记（`onAreaChange` 会在每次尺寸变化时重读，别刷日志）。
      const line: string = `system=${sys.topRect.height} cutout=${cutout.topRect.height}` +
        ` nav=${bottom.bottomRect.height} -> vp top=${this.windowState.safeTop} bottom=${this.windowState.safeBottom}`;
      if (line !== this.lastSafeAreaLog) {
        this.lastSafeAreaLog = line;
        Logger.info('Shell', `safe area px: ${line}`);
      }
    } catch (e) {
      Logger.error('Shell', `safe area query failed: ${e}`);
    }
  }

  @Builder
  tabHot() {
    Column({ space: 2 }) {
      SymbolGlyph($r('sys.symbol.flame'))
        .fontSize(22)
        .fontColor([this.currentTab === 0
          ? $r('app.color.brand') : $r('app.color.text_secondary')])
      Text('热门')
        .fontSize(11)
        .fontColor(this.currentTab === 0
          ? $r('app.color.brand') : $r('app.color.text_secondary'))
    }
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  tabSub() {
    Column({ space: 2 }) {
      SymbolGlyph($r('sys.symbol.bell'))
        .fontSize(22)
        .fontColor([this.currentTab === 1
          ? $r('app.color.brand') : $r('app.color.text_secondary')])
      Text('订阅')
        .fontSize(11)
        .fontColor(this.currentTab === 1
          ? $r('app.color.brand') : $r('app.color.text_secondary'))
    }
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  tabRank() {
    Column({ space: 2 }) {
      SymbolGlyph($r('sys.symbol.ranking_fill'))
        .fontSize(22)
        .fontColor([this.currentTab === 2
          ? $r('app.color.brand') : $r('app.color.text_secondary')])
      Text('排行')
        .fontSize(11)
        .fontColor(this.currentTab === 2
          ? $r('app.color.brand') : $r('app.color.text_secondary'))
    }
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  tabMine() {
    Column({ space: 2 }) {
      SymbolGlyph($r('sys.symbol.person'))
        .fontSize(22)
        .fontColor([this.currentTab === 3
          ? $r('app.color.brand') : $r('app.color.text_secondary')])
      Text('我的')
        .fontSize(11)
        .fontColor(this.currentTab === 3
          ? $r('app.color.brand') : $r('app.color.text_secondary'))
    }
    .padding({ top: 4, bottom: 4 })
  }

  /** 冷启动重应用显示模式（`setColorMode` 只运行时有效；落盘值在此重放）。 */
  private applyDisplayMode(): void {
    try {
      const settings: AppSettings = PersistenceV2.globalConnect({
        type: AppSettings,
        key: 'AppSettings9',
        defaultCreator: () => new AppSettings()
      })!;
      const host = this.getUIContext().getHostContext() as common.Context;
      host.getApplicationContext()
        .setColorMode(displayModeToColorMode(settings.displayMode));
    } catch (e) {
      Logger.error('Shell', `apply display mode failed: ${e}`);
    }
  }

  /** 当前 tab 的滚动器（标题栏 `bindToScrollable` 只跟当前页走）。 */
  private currentScroller(): Scroller {
    if (this.currentTab === 1) {
      return this.scrollerSub;
    } else if (this.currentTab === 2) {
      return this.scrollerRank;
    } else if (this.currentTab === 3) {
      return this.scrollerMine;
    }
    return this.scrollerHot;
  }

  /**
   * 解析后是否为深色（状态栏图标色用）。
   * 依赖 `displayMode`（应用内切换）+ `configVersion`（系统级切换经 `onConfigurationUpdate` 递增），
   * 任一变化即重算，不在 `build` 里做一次性快照。
   */
  @Computed get statusDark(): boolean {
    // 订阅系统配置版本（值本身不用，只为建立依赖）。
    const version: number = this.session.configVersion;
    if (this.settings.displayMode === 2) {
      return true;
    }
    if (this.settings.displayMode === 1) {
      return false;
    }
    try {
      const ctx: common.Context =
        this.getUIContext().getHostContext() as common.Context;
      const colorMode = ctx.getApplicationContext().resourceManager.getConfigurationSync().colorMode;
      return version >= 0 && colorMode === resourceManager.ColorMode.DARK;
    } catch (e) {
      Logger.error('Shell', `color mode query failed: ${e}`);
      return false;
    }
  }

  /** 标题栏搜索入口（"我的"页豁免；HDS 菜单区放大镜图标）。 */
  private searchMenu(): HdsNavigationMenuContentOptions | undefined {
    if (this.currentTab === 3) {
      return undefined;
    }
    return {
      value: [{
        content: {
          icon: new SymbolGlyphModifier($r('sys.symbol.magnifyingglass'))
            .fontColor([$r('app.color.text_primary')]),
          action: () => {
            this.pageStack.pushPath({ name: '搜索' });
          }
        }
      }]
    };
  }

  /** 排行档位：互斥选项用官方胶囊段选（分段按钮自带选中浮起，比高饱和 chip 更接近系统观感）。 */
  private rankSegmentItems(): SegmentButtonV2Items {
    const options: SegmentButtonV2ItemOptions[] = [];
    for (let i = 0; i < RANK_RANGES.length; i++) {
      options.push({ text: RANK_RANGES[i].label });
    }
    return new SegmentButtonV2Items(options);
  }

  private rankIndex(): number {
    for (let i = 0; i < RANK_RANGES.length; i++) {
      if (RANK_RANGES[i].range === this.rankState.range) {
        return i;
      }
    }
    return 0;
  }

  @Builder
  rankChips() {
    Row() {
      CapsuleSegmentButtonV2({
        items: this.rankSegmentItems(),
        selectedIndex: this.rankIndex(),
        $selectedIndex: (index: number) => {
          if (index >= 0 && index < RANK_RANGES.length) {
            this.rankState.select(RANK_RANGES[index].range);
          }
        }
      })
        .width('100%')
        .height(36)
    }
    .width('100%')
    .height(52)
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
  }

  @Builder
  pageMap(name: string) {
    if (name === '搜索') {
      SearchPage();
    } else if (name === '详情') {
      GalleryDetailPage();
    } else if (name === '评论') {
      CommentsPage();
    } else if (name === '收藏') {
      FavoritesPage();
    } else if (name === '历史') {
      HistoryPage();
    } else if (name === '屏蔽') {
      BlockListPage();
    } else if (name === '阅读') {
      ReaderPage();
    } else if (name === '设置') {
      SettingsPage();
    } else if (name === '下载') {
      DownloadsPage();
    }
  }

  build() {
    HdsNavigation(this.pageStack) {
      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          DiscoverListPage({ mode: 'popular', pageStack: this.pageStack, scroller: this.scrollerHot })
        }
        .tabBar(this.tabHot)
        TabContent() {
          DiscoverListPage({ mode: 'watched', pageStack: this.pageStack, scroller: this.scrollerSub })
        }
        .tabBar(this.tabSub)
        TabContent() {
          TopListPage({ pageStack: this.pageStack, scroller: this.scrollerRank })
        }
        .tabBar(this.tabRank)
        TabContent() {
          MyPage({ pageStack: this.pageStack, scroller: this.scrollerMine })
        }
        .tabBar(this.tabMine)
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barFloatingStyle({
        barBottomMargin: 28,
        // 沉浸光感：与标题栏同一档位令牌（`ui/Materials.ets` 单点改档）。
        systemMaterialEffect: HDS_MATERIAL
      })
      .onChange((index: number) => {
        this.currentTab = index;
      })
    }
    .titleBar({
      // 标题栏主动避让状态栏：文字/菜单落到状态栏下方，背景仍可透明铺满。
      avoidLayoutSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          // 官方「渐变模糊」：模糊强度在空间上渐变（边界柔和），是增强沉浸感的推荐档位；
          // 之前的 GRADUAL_BLUR 是随滚动距离加深、边界仍是硬的。
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_H)
        },
        blurStrategy: BlurStrategy.ADAPTIVE,
        // 顶部透明底 + 标题钉死主题文字色（默认浅色内容在浅色列表上不可见）；
        // 滚动态不再铺不透明底色（会遮住材质），交给 GRADUAL_BLUR + systemMaterialEffect 合成。
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: { titleStyle: { mainTitleColor: $r('app.color.text_primary') } }
        },
        scrollEffectStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent }
        },
        // 沉浸光感：标题栏走系统材质（官方 ADAPTIVE 策略，按设备算力自适应）。
        systemMaterialEffect: HDS_MATERIAL
      },
      content: {
        title: { mainTitle: TAB_TITLES[this.currentTab] },
        menu: this.searchMenu(),
        // 排行档位胶囊：进标题栏底部功能区（不再被渐变层半遮挡）；其他 tab 不占高度。
        bottomBuilder: this.currentTab === 2
          ? { builder: () => { this.rankChips() }, height: RANK_CHIPS_H }
          : undefined
      }
    })
    // 状态栏图标跟主题走（顶部透明底时系统默认浅色图标在浅色列表上不可见）；
    // 滚动态走 HDS 默认。双参签名见 HDS `hdsBaseComponent.d.ets:2363`。
    .systemBarStyle({
      statusBarContentColor: this.statusDark ? '#E5FFFFFF' : '#E6000000'
    }, undefined)
    // 标题栏常驻 + 官方渐变模糊：内容从下方穿过时边界柔和（不再整条隐藏/硬边）。
    .bindToScrollable([this.currentScroller()])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    // 官方沉浸式：整块导航（标题栏 + 内容区）扩展到系统栏区域，安全区由 HDS/组件自行避让。
    // 不再用 `.padding({top})` 手动推下去（那会留一条平的窗口底色，见 FAQ faqs-arkui-897）。
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    // 折叠屏展开 / 横竖屏切换后重新量安全区（尺寸变化 → 重读，不写死）。
    .onAreaChange(() => {
      this.applySafeArea();
    })
    // 折叠屏展开不断裂：Auto 会在宽屏进分栏（左 NavBar + 右空 content），强制 Stack 单栏铺满。
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .onAppear(() => {
      this.refreshLoginState();
      this.applyDisplayMode();
      this.applySafeArea();
      this.initDownloads();
    })
  }
}
