import { common } from '@kit.AbilityKit';
import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { EhSite, EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { GalleryInfo } from '../model/GalleryInfo';
import { Logger } from '../common/Logger';
import { errorText } from '../common/ErrorText';
import { GalleryRow, GalleryRowItem, loadMissingThumbs, pushGalleryDetail } from './GalleryRow';
import { AppSettings } from '../state/AppSettings';
import { WindowState } from '../state/WindowState';
import { PagedDataSource } from '../common/PagedList';
import { PAGE_PADDING, CARD_GAP, TAB_BAR_CLEARANCE } from './Materials';
import { RankState } from '../state/RankState';
import { TITLE_BAR_H, RANK_CHIPS_H } from './NavStyle';
import { RefreshSpinner } from './RefreshSpinner';

/**
 * 排行榜（分档画廊榜；`?tl=` 页与首页同构，复用 `GalleryListParser` + `GalleryRow`）。
 * 档位胶囊在 `AppShell` 标题栏（`RankState` 写、本页 `@Monitor` 订阅）；换档重置 `page=0` 重取。
 */
@ComponentV2
export struct TopListPage {
  @Require @Param pageStack: NavPathStack;
  /** 外部滚动联动（`AppShell` 按 tab 持有，标题栏渐进模糊用；`List` 绑定）。 */
  @Require @Param scroller: Scroller;
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  @Local rankState: RankState = AppStorageV2.connect(RankState, () => new RankState())!;
  /** 系统安全区（顶部避让 = safeTop + 标题栏高 + 档位胶囊 52 + 8 呼吸）。 */
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

  /** 标题栏胶囊换档 → 重取（`version` 每次真正换档 +1；同档点击不触发）。 */
  @Monitor('rankState.version')
  onRankRangeChange(_monitor: IMonitor): void {
    this.load(true);
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
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      this.message = '加载中…';
      const list: GalleryInfo[] = await client.getGalleryList(site, EhUrl.toplist(this.rankState.range, this.page), this.settings.thumbSize);
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
      this.message = this.items.length === 0 ? '该榜单暂无内容' : '';
      this.dataSource.setItems(this.items, mapped.length > 0);
      this.page += 1;
      loadMissingThumbs(this.context(), client, site, this.items).catch((_e: object) => {
        // 缩略图补齐失败不影响列表
      });
    } catch (e) {
      Logger.error('Discover', `toplist load failed: ${e}`);
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
            // 顶部留白（随滚带走）：标题栏（56）+ 档位胶囊功能区（52）+ 8 呼吸空间。
            ListItem() {
              Column().height(this.windowState.safeTop + TITLE_BAR_H + RANK_CHIPS_H + 8)
            }
            // 空态 / 加载 / 错误：放在 List 里（做成 Stack 的兄弟节点会被挤成 0 高，见 `DiscoverListPage` 同处注释）。
            if (this.items.length === 0 && this.message.length > 0) {
              ListItem() {
                Row({ space: 8 }) {
                  if (this.message.endsWith('…')) {
                    LoadingProgress().width(32).height(32)
                  }
                  Text(this.message)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ top: 96 })
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
            // 底部给悬浮 tab 胶囊留位（运行时安全区 + 胶囊高度）。
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
          top: this.windowState.safeTop + TITLE_BAR_H + RANK_CHIPS_H + 8
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
