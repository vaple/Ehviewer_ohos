import { common } from '@kit.AbilityKit';
import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { Logger } from '../common/Logger';
import { GalleryRow, GalleryRowItem, loadMissingThumbs, pushGalleryDetail } from './GalleryRow';
import { GalleryRowSkeleton, SKELETON_ROW_INDICES } from './GalleryRowSkeleton';
import { AppSettings } from '../state/AppSettings';
import { WindowState } from '../state/WindowState';
import { FilterDao } from '../db/dao/FilterDao';
import { DbHelper } from '../db/DbHelper';
import { Filter } from '../model/Filter';
import { exclusionQueryOf } from '../search/SearchQuery';
import { GalleryListFeed } from './GalleryListFeed';
import { GalleryListPage } from '../parser/GalleryListParser';
import { PagedDataSource, PREFETCH_TAIL, shouldFetchMore } from '../common/PagedList';
import { CARD_GAP, PAGE_PADDING, TAB_BAR_CLEARANCE } from './Materials';
import { TITLE_BAR_H } from './NavStyle';
import { RefreshSpinner } from './RefreshSpinner';
import { errorText } from '../common/ErrorText';

/** 发现列表模式（订阅 / 热门；排行另见 `TopListPage`）。 */
export type DiscoverMode = 'watched' | 'popular';

/**
 * 订阅 / 热门列表（与首页同构，复用 `GalleryListParser` + `GalleryRow`；独立 `page/items`）。
 * 订阅需登录（`ipb_member_id` 缺失则人话提示、不发请求）；热门单页，触底不再取。
 */
@ComponentV2
export struct DiscoverListPage {
  @Require @Param mode: DiscoverMode;
  @Require @Param pageStack: NavPathStack;
  /** 外部滚动联动（`AppShell` 按 tab 持有，标题栏渐进模糊用；`List` 绑定）。 */
  @Require @Param scroller: Scroller;
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  /** 系统安全区（顶部避让 = safeTop + 标题栏高 + 8 呼吸）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  @Local items: GalleryRowItem[] = [];
  @Local isRefreshing: boolean = false;
  /** 当前下拉距离（vp，来自 `Refresh.onOffsetChange`），只用于刷新圈的淡入。 */
  @Local pullOffset: number = 0;
  @Local message: string = '加载中…';
  private isLoading: boolean = false;
  /** 分页状态唯一持有者（items / 下一页游标 / 已访问 URL）。 */
  private feed: GalleryListFeed = new GalleryListFeed(async (url: string): Promise<GalleryListPage> => {
    return this.fetchPage(url);
  });
  /** 懒加载数据源（只负责 items + hasMore；预取由页面在滚动到底时显式触发）。 */
  private dataSource: PagedDataSource<GalleryRowItem> =
    new PagedDataSource<GalleryRowItem>(() => {
      return this.isLoading;
    });

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  /** 取一页（供 feed 回调；每次新建 client 与旧实现一致，避免跨页持有 Cookie 快照）。 */
  private async fetchPage(url: string): Promise<GalleryListPage> {
    const cookies: CookieStore = new CookieStore();
    await cookies.init(this.context());
    const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
    return client.getGalleryList(this.settings.site, url, this.settings.thumbSize);
  }

  private async load(refresh: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      if (this.mode === 'watched' && !cookies.has('ipb_member_id')) {
        this.message = '登录后查看订阅';
        this.isRefreshing = false;
        this.isLoading = false;
        return;
      }
      let url: string;
      if (this.mode === 'watched') {
        // `/watched` 支持完整搜索参数：把「搜索排除」拼成 f_search（与关键词搜索同一套规则）。
        let excl: string = '';
        try {
          await DbHelper.init(this.context());
          const rules: Filter[] = (await FilterDao.queryAll()).filter((f: Filter) => f.enable);
          excl = exclusionQueryOf(rules, []);
        } catch (e) {
          Logger.error('Block', `exclusions load failed: ${e}`);
        }
        url = EhUrl.watched(site, 0, excl);
      } else {
        url = EhUrl.popular(site);
      }
      this.message = '加载中…';
      // refresh 时 feed 从 url 重新开始；否则顺着上一页给的 next 走（next 为 null 即到底）。
      await this.feed.load(url, refresh);
      this.items = this.feed.items;
      if (this.items.length === 0) {
        this.message = this.mode === 'watched' ? '暂无订阅' : '暂无热门';
      } else {
        this.message = '';
      }
      this.dataSource.setItems(this.items, this.feed.hasMore);
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      loadMissingThumbs(this.context(), client, site, this.items).catch((_e: object) => {
        // 缩略图补齐失败不影响列表
      });
    } catch (e) {
      Logger.error('Discover', `${this.mode} load failed: ${e}`);
      this.message = errorText(e as Object);
    }
    this.isRefreshing = false;
    this.isLoading = false;
  }

  /** `Refresh` 内置区域留空：圈由 `RefreshSpinner` 画在内容起始线（见 `ui/RefreshSpinner.ets`）。 */
  @Builder
  emptyRefreshArea() {
    Column().width('100%')
  }

  build() {
    Column() {
        Stack({ alignContent: Alignment.Top }) {
        Refresh({ refreshing: $$this.isRefreshing, builder: this.emptyRefreshArea() }) {
          List({ scroller: this.scroller }) {
            // 顶部留白（随滚带走）：给标题栏让位，避免首行被标题压住。
            ListItem() {
              Column().height(this.windowState.safeTop + TITLE_BAR_H + 8)
            }
            // 首屏骨架行（内容未到时与真行同尺寸，出数据不跳版式）。
            if (this.items.length === 0 && this.message.endsWith('…')) {
              Repeat(SKELETON_ROW_INDICES)
                .each((_ri: RepeatItem<number>) => {
                  ListItem() {
                    GalleryRowSkeleton()
                  }
                  .padding({ left: PAGE_PADDING, right: PAGE_PADDING, bottom: CARD_GAP })
                })
                .key((i: number) => `sk-${i}`)
            }
            // 空态 / 加载 / 错误：**必须作为 ListItem 放在 List 里**。
            // 做成 `Stack` 的兄弟节点会被挤成 0 高（List 是 `height('100%')`，Stack 已占满整页），
            // 页面就只剩一片空白（连节点都不会出现在 layout 里）。
            if (this.items.length === 0 && this.message.length > 0 && !this.message.endsWith('…')) {
              ListItem() {
                if (this.message === '暂无订阅') {
                  // 订阅空态：直接给去官方 My Tags 关注的引导（订阅内容由 My Tags 的 Watched 决定）。
                  Column({ space: 10 }) {
                    Text(this.message)
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Text('在 My Tags 里给标签勾上 Watched，这里就会出现它们的更新。')
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .textAlign(TextAlign.Center)
                    Button('去设置页打开 My Tags')
                      .fontSize(14)
                      .onClick(() => {
                        this.pageStack.pushPathByName('设置', undefined);
                      })
                  }
                  .width('100%')
                  .padding({ top: 96, left: 24, right: 24 })
                } else {
                  Text(this.message)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding({ top: 96 })
                }
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
            // 底部给悬浮 tab 胶囊留位（运行时安全区 + 胶囊高度），最后一行不会被压住。
            ListItem() {
              Column().height(this.windowState.safeBottom + TAB_BAR_CLEARANCE)
            }
          }
          .width('100%')
          .height('100%')
          .cachedCount(4)
          // 预取：滚到尾部窗口就问一次（`getData` 不再有副作用，见 `ui/AGENTS.md` #66）。
          .onScrollIndex((_start: number, end: number) => {
            if (shouldFetchMore(this.items.length, end + PREFETCH_TAIL, this.feed.hasMore, this.isLoading)) {
              this.load(false);
            }
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
        .onRefreshing(() => { this.load(true); })
        .onOffsetChange((v: number) => { this.pullOffset = v; })
        .onStateChange((s: RefreshStatus) => {
          if (s === RefreshStatus.Done) {
            this.pullOffset = 0;
          }
        })
        .layoutWeight(1)
        RefreshSpinner({
          pullOffset: this.pullOffset,
          isRefreshing: this.isRefreshing,
          top: this.windowState.safeTop + TITLE_BAR_H + 8
        })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_primary'))
      .onAppear(() => {
        if (this.items.length === 0) {
          this.load(true);
        }
      })
  }
}
