import { common } from '@kit.AbilityKit';
import { AppStorageV2, PersistenceV2, SymbolGlyphModifier, promptAction } from '@kit.ArkUI';
import { EhSite } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient, FavPage } from '../network/EhClient';
import { GalleryInfo } from '../model/GalleryInfo';
import { DetailParam } from '../model/DetailParam';
import { Logger } from '../common/Logger';
import { errorText } from '../common/ErrorText';
import { AppSettings } from '../state/AppSettings';
import { WindowState } from '../state/WindowState';
import { HdsListItem, HdsNavDestination, PrefixImage } from '@kit.UIDesignKit';
import { PagedDataSource } from '../common/PagedList';
import { GalleryRowItem, loadMissingThumbs, rowLine1, rowLine2, toDetailPreview } from './GalleryRow';
import { catLabel } from './CategoryStyle';
import { FavCatSheet, FavCatOption } from './FavCatSheet';
import { SHEET_MATERIAL, PAGE_PADDING, TOUCH_MIN } from './Materials';
import { navTitleBarStyle, TITLE_BAR_H } from './NavStyle';

/**
 * 多选集合切换（纯函数：已在则去，否则加；返回新数组，调用方整体替换）。
 * 行为即断言，见 `FavoritesBatch.test`。
 */
export function toggleGid(selected: number[], gid: number): number[] {
  if (selected.indexOf(gid) >= 0) {
    return selected.filter((g: number) => g !== gid);
  }
  return selected.concat([gid]);
}

/**
 * 云收藏（源 `FavoritesScene` 子集）：类 tabs（含计数）+ 收藏内搜索 + 排序切换 + 行移动/删除。
 * 单向同步：以服务端为准，本地库不再引用（存量旧数据直接丢弃）。
 * 未登录人话提示、不发请求。
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
  @Local order: string = 'p';
  @Local cats: string[] = [];
  @Local counts: number[] = [];
  @Local items: GalleryRowItem[] = [];
  @Local message: string = '加载中…';
  /** 待移动画廊 gid（`-1` = 未开类选择器）。 */
  @Local moveGid: number = -1;
  /** 多选态（选中 gid 集合，不落盘；退出多选即清空）。 */
  @Local selectedGids: number[] = [];
  /** 多选模式开关（批量移动到 0–9 / 删除走底部栏）。 */
  @Local selectMode: boolean = false;
  /** 批量移动：类选择器为批量服务（`moveGid` 单条逻辑不动）。 */
  @Local batchMove: boolean = false;
  private moveToken: string = '';
  private page: number = 0;
  /** 系统安全区（顶部避让 = safeTop + 标题栏高）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  /** 收藏列表滚动器（标题栏渐变模糊用）。 */
  private scroller: Scroller = new Scroller();
  private isLoading: boolean = false;
  /** 懒加载数据源（`LazyForEach` 官方范式；`getData` 进入尾部窗口即预取下一页）。 */
  private dataSource: PagedDataSource<GalleryRowItem> =
    new PagedDataSource<GalleryRowItem>(() => {
      this.load(false);
    }, () => {
      return this.isLoading;
    });
  private pageStack: NavPathStack | undefined = undefined;

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private clientOf(cookies: CookieStore): EhClient {
    return new EhClient(new RcpHttpClient(), cookies);
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
    const options: SelectOption[] = [{ value: '全部' }];
    for (let i = 0; i < this.cats.length && i < 10; i++) {
      const count: number = i < this.counts.length ? this.counts[i] : 0;
      options.push({ value: `${this.cats[i]} (${count})` });
    }
    return options;
  }

  private catSelectLabel(): string {
    if (this.favCat < 0) {
      return '全部';
    }
    const count: number = this.favCat < this.counts.length ? this.counts[this.favCat] : 0;
    return `${this.catNameOf(this.favCat)} (${count})`;
  }

  /** 排序方式菜单（`p` 发布时间 / `f` 收藏时间；点在图标上弹出，当前项打勾）。 */
  @Builder
  sortMenu() {
    Menu() {
      MenuItem({
        content: '按发布时间',
        symbolEndIcon: this.order === 'p'
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          this.setOrder('p').catch((_e: object) => {
            // 错误已在 setOrder 内处理
          });
        })
      MenuItem({
        content: '按收藏时间',
        symbolEndIcon: this.order === 'f'
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          this.setOrder('f').catch((_e: object) => {
            // 错误已在 setOrder 内处理
          });
        })
    }
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
      if (!cookies.has('ipb_member_id')) {
        this.items = [];
        this.cats = [];
        this.counts = [];
        this.message = '登录后查看云收藏';
        this.isLoading = false;
        return;
      }
      const client: EhClient = this.clientOf(cookies);
      this.message = '加载中…';
      const fav: FavPage =
        await client.getCloudFavorites(site, this.favCat, this.keyword, this.page, this.settings.thumbSize);
      const mapped: GalleryRowItem[] = this.toRowItems(fav.items);
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
      this.cats = fav.cats;
      this.counts = fav.counts;
      if (fav.order.length > 0) {
        this.order = fav.order;
      }
      this.message = this.items.length === 0 ? '还没有云收藏' : '';
      this.dataSource.setItems(this.items, mapped.length > 0);
      this.page += 1;
      loadMissingThumbs(this.context(), client, site, this.items).catch((_e: object) => {
        // 缩略图补齐失败不影响列表
      });
    } catch (e) {
      Logger.error('Fav', `cloud load failed: ${e}`);
      this.message = errorText(e as Object);
    }
    this.isLoading = false;
  }

  private async setOrder(next: string): Promise<void> {
    if (this.isLoading || this.order === next) {
      return;
    }
    try {
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      if (!cookies.has('ipb_member_id')) {
        promptAction.showToast({ message: '登录后查看云收藏' });
        return;
      }
      const client: EhClient = this.clientOf(cookies);
      const site: EhSite = this.settings.site;
      await client.setFavOrder(site, next, this.favCat, this.keyword, this.page);
      await this.load(true);
    } catch (e) {
      Logger.error('Fav', `sort failed: ${e}`);
      promptAction.showToast({ message: '切换排序失败，请重试' });
    }
  }

  private async moveTo(cat: number): Promise<void> {
    const gid: number = this.moveGid;
    const token: string = this.moveToken;
    this.moveGid = -1;
    this.moveToken = '';
    if (gid < 0) {
      return;
    }
    let catName: string = `收藏夹${cat}`;
    for (let i = 0; i < this.cats.length && i < 10; i++) {
      if (i === cat) {
        catName = this.cats[i];
        break;
      }
    }
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

  private setSelectMode(on: boolean): void {
    this.selectMode = on;
    this.selectedGids = [];
    if (!on) {
      this.batchMove = false;
    }
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

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          List({ space: 8, scroller: this.scroller }) {
            // 顶部避让放进滚动内容（内容钻到标题栏下，渐变模糊才生效）。
            ListItem() {
              Column().height(this.windowState.safeTop + TITLE_BAR_H)
            }
            // 分类 / 排序 / 多选 与搜索框放进列表：滚动时一起钻到标题栏下（否则标题会压住它们）。
            ListItem() {
              Row({ space: 8 }) {
                // 分类：官方 Select（全部 + 10 个收藏夹；不再横向滚动被截断）。
                Select(this.catOptions())
                  .selected(this.favCat + 1)
                  .value(this.catSelectLabel())
                  .height(36)
                  .constraintSize({ maxWidth: 190 })
                  .onSelect((index: number, _value: string) => {
                    if (index - 1 !== this.favCat) {
                      this.favCat = index - 1;
                      this.load(true);
                    }
                  })
                Blank()
                SymbolGlyph($r('sys.symbol.sort'))
                  .fontSize(20)
                  .fontColor([$r('app.color.text_secondary')])
                  .width(TOUCH_MIN)
                  .height(TOUCH_MIN)
                  .padding(6)
                  .accessibilityText('排序方式')
                  .bindMenu(this.sortMenu)
                SymbolGlyph($r('sys.symbol.checkmark_circle'))
                  .fontSize(20)
                  .fontColor([this.selectMode
                    ? $r('app.color.brand') : $r('app.color.text_secondary')])
                  .width(TOUCH_MIN)
                  .height(TOUCH_MIN)
                  .padding(6)
                  .accessibilityText('多选')
                  .onClick(() => {
                    this.setSelectMode(!this.selectMode);
                  })
              }
              .width('100%')
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 8, bottom: 4 })
            }
            ListItem() {
              Row() {
                Search({ value: this.keyword, placeholder: '收藏内搜索' })
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.keyword = value;
                  })
                  .onSubmit(() => {
                    this.load(true);
                  })
              }
              .width('100%')
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING, bottom: 4 })
            }
            LazyForEach(this.dataSource, (item: GalleryRowItem) => {
              HdsListItem({
                hdsListItemCard: {
                  prefixItem: item.thumb.length > 0
                    ? new PrefixImage({ image: item.thumb })
                    : undefined,
                  textItem: {
                    primaryText: {
                      text: item.title.length > 0 ? item.title : `gid ${item.gid}`
                    },
                    secondaryText: rowLine1(item).length > 0
                      ? { text: `${catLabel(item.category)} · ${rowLine1(item)}` }
                      : { text: catLabel(item.category) },
                    description: rowLine2(item).length > 0
                      ? { text: rowLine2(item) }
                      : undefined
                  },
                  onClick: () => {
                    if (this.selectMode) {
                      this.selectedGids = toggleGid(this.selectedGids, item.gid);
                    } else {
                      const param: DetailParam = { gid: item.gid, token: item.token, preview: toDetailPreview(item) };
                      this.pageStack?.pushPathByName('详情', param);
                    }
                  }
                },
                isSelected: this.selectMode &&
                  this.selectedGids.indexOf(item.gid) >= 0,
                swipeActionOptions: this.selectMode ? undefined : {
                  icons: [
                    {
                      icon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil'))
                        .fontColor([Color.White]).fontSize(20),
                      onAction: () => {
                        this.moveGid = item.gid;
                        this.moveToken = item.token;
                      }
                    }
                  ],
                  deleteIconOptions: {
                    onAction: () => {
                      this.confirmDelete(item.gid, item.token, item.title);
                    }
                  }
                }
              })
            }, (item: GalleryRowItem) => `${item.gid}`)
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(4)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
          if (this.selectMode) {
            Row({ space: 16 }) {
              Text(`已选 ${this.selectedGids.length} 项`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.square_and_pencil'))
                  .fontSize(16)
                  .fontColor([$r('app.color.brand')])
                Text('移动到')
                  .fontSize(13)
                  .fontColor($r('app.color.brand'))
              }
              .padding(8)
              .onClick(() => {
                if (this.selectedGids.length === 0) {
                  promptAction.showToast({ message: '先选择要移动的收藏' });
                  return;
                }
                this.batchMove = true;
              })
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(16)
                  .fontColor([$r('app.color.danger')])
                Text('删除')
                  .fontSize(13)
                  .fontColor($r('app.color.danger'))
              }
              .padding(8)
              .onClick(() => {
                this.confirmBatchDelete();
              })
            }
            .width('100%')
            .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 8, bottom: 8 })
            .alignItems(VerticalAlign.Center)
          }
          if (this.message.length > 0) {
            if (this.message.endsWith('…')) {
              Column() {
                LoadingProgress().width(32).height(32)
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else {
              Text(this.message)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .padding(6)
            }
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.bg_primary'))
        .onAppear(() => {
          this.load(true);
        })
      }
      .width('100%')
      .height('100%')
      // 移动收藏夹：官方半模态 + 系统材质（原自绘遮罩浮层已删）。
      .bindSheet(this.moveGid >= 0 || this.batchMove, this.catSheet(), {
        title: { title: '移动到收藏夹' },
        // 内容是 List（无固有高度，`FIT_CONTENT` 量不出来）：半屏起步，可上拖到全屏。
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        systemMaterial: SHEET_MATERIAL,
        onDisappear: () => {
          this.moveGid = -1;
          this.moveToken = '';
          this.batchMove = false;
        }
      })
    }
    .titleBar({ avoidLayoutSafeArea: true, style: navTitleBarStyle(), content: { title: { mainTitle: '收藏' } } })
    .bindToScrollable([this.scroller])
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
    })
  }
}
