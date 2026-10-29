import { common } from '@kit.AbilityKit';
import { AppStorageV2, PersistenceV2, SymbolGlyphModifier, promptAction } from '@kit.ArkUI';
import { EhSite } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { HistoryInfo } from '../model/HistoryInfo';
import { Logger } from '../common/Logger';
import { DbHelper } from '../db/DbHelper';
import { HistoryDao } from '../db/dao/HistoryDao';
import { AppSettings } from '../state/AppSettings';
import { WindowState } from '../state/WindowState';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { GalleryRow, GalleryRowItem, loadMissingThumbs, pushGalleryDetail } from './GalleryRow';
import { CARD_GAP, PAGE_PADDING } from './Materials';
import { navTitleBarStyle, TITLE_BAR_H } from './NavStyle';

/** 浏览历史列表（读实时库 TIME 倒序；点行进详情；清空需确认）。 */
@ComponentV2
export struct HistoryPage {
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  @Local items: GalleryRowItem[] = [];
  @Local message: string = '加载中…';
  private pageStack: NavPathStack | undefined = undefined;
  /** 系统安全区（顶部避让 = safeTop + 标题栏高）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  /** 历史列表滚动器（标题栏渐变模糊用）。 */
  private scroller: Scroller = new Scroller();

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private toRowItems(list: HistoryInfo[]): GalleryRowItem[] {
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

  private async reload(): Promise<void> {
    try {
      await DbHelper.init(this.context());
      this.items = this.toRowItems(await HistoryDao.queryAll());
      this.message = this.items.length === 0 ? '还没有浏览记录' : '';
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      loadMissingThumbs(this.context(), client, site, this.items).catch((_e: object) => {
        // 缩略图补齐失败不影响列表
      });
    } catch (e) {
      Logger.error('Db', `history load failed: ${e}`);
      this.message = '历史读取失败';
    }
  }

  private confirmClear(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '清空历史',
      message: '确定清空全部浏览记录吗？',
      buttons: [{ text: '再想想', color: '#8C8C8C' }, { text: '确定', color: '#3D6BE5' }]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        HistoryDao.clear()
          .then(() => this.reload())
          .catch((e: object) => {
            Logger.error('Db', `history clear failed: ${e}`);
            promptAction.showToast({ message: '操作失败，请重试' });
          });
      }
    }).catch((_e: object) => {
      // 对话框自身失败不影响列表
    });
  }

  build() {
    HdsNavDestination() {
      Column() {
        List({ scroller: this.scroller }) {
          // 顶部避让放在滚动内容里：内容可钻到标题栏下（渐变模糊才有内容穿过）。
          ListItem() {
            Column().height(this.windowState.safeTop + TITLE_BAR_H)
          }
          Repeat(this.items)
            .virtualScroll({ reusable: false })
            .each((ri: RepeatItem<GalleryRowItem>) => {
              ListItem() {
                GalleryRow({ item: ri.item })
                  .onClick(() => {
                    pushGalleryDetail(this.getUIContext(), this.pageStack, ri.item);
                  })
              }
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING, bottom: CARD_GAP })
            })
            .key((item: GalleryRowItem) => `${item.gid}`)
        }
        .width('100%')
        .layoutWeight(1)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
        this.reload();
      })
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      style: navTitleBarStyle(),
      content: {
        title: { mainTitle: '历史' },
        // 清空入口统一放右上角（与详情页的菜单同款 HDS 图标，不再占列表一行）。
        menu: {
          value: [{
            content: {
              icon: new SymbolGlyphModifier($r('sys.symbol.trash'))
                .fontColor([this.items.length > 0 ? $r('app.color.danger') : $r('app.color.text_secondary')]),
              action: () => {
                if (this.items.length > 0) {
                  this.confirmClear();
                }
              }
            }
          }]
        }
      }
    })
    .bindToScrollable([this.scroller])
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
    })
  }
}
