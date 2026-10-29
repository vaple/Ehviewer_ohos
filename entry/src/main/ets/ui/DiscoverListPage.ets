import { common } from '@kit.AbilityKit';
import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { GalleryInfo } from '../model/GalleryInfo';
import { Logger } from '../common/Logger';
import { GalleryRow, GalleryRowItem, loadMissingThumbs, pushGalleryDetail } from './GalleryRow';
import { AppSettings } from '../state/AppSettings';
import { WindowState } from '../state/WindowState';
import { FilterDao } from '../db/dao/FilterDao';
import { DbHelper } from '../db/DbHelper';
import { Filter } from '../model/Filter';
import { exclusionQueryOf } from '../search/SearchQuery';
import { PagedDataSource } from '../common/PagedList';
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
  private page: number = 0;
  private isLoading: boolean = false;
  /** 懒加载数据源（`LazyForEach` 官方范式；`getData` 进入尾部窗口即预取下一页）。 */
  private dataSource: PagedDataSource<GalleryRowItem> =
    new PagedDataSource<GalleryRowItem>(() => {
      this.load(false);
    }, () => {
      return this.isLoading;
    });

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
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

  private async load(refresh: boolean): Promise<void> {
    if (this.isLoading) {
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
      if (this.mode === 'watched' && !cookies.has('ipb_member_id')) {
        this.message = '登录后查看订阅';
        this.isRefreshing = false;
        this.isLoading = false;
        return;
      }
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
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
        url = EhUrl.watched(site, this.page, excl);
      } else {
        url = EhUrl.popular(site);
      }
      this.message = '加载中…';
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
      if (this.items.length === 0) {
        this.message = this.mode === 'watched' ? '暂无订阅' : '暂无热门';
      } else {
        this.message = '';
      }
      this.dataSource.setItems(this.items,
        this.mode === 'watched' && mapped.length > 0);
      this.page += 1;
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
            // 空态 / 加载 / 错误：**必须作为 ListItem 放在 List 里**。
            // 做成 `Stack` 的兄弟节点会被挤成 0 高（List 是 `height('100%')`，Stack 已占满整页），
            // 页面就只剩一片空白（连节点都不会出现在 layout 里）。
            if (this.items.length === 0 && this.message.length > 0) {
              ListItem() {
                if (this.message.endsWith('…')) {
                  Column({ space: 8 }) {
                    LoadingProgress().width(32).height(32)
                    Text(this.message)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .width('100%')
                  .padding({ top: 96 })
                } else if (this.message === '暂无订阅') {
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
