import { common } from '@kit.AbilityKit';
import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { EhSite } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { GalleryDetail } from '../model/GalleryDetail';
import { GalleryComment } from '../model/GalleryComment';
import { DetailParam } from '../model/DetailParam';
import { errorText } from '../common/ErrorText';
import { Logger } from '../common/Logger';
import { GalleryDetailParser } from '../parser/GalleryDetailParser';
import { AppSettings } from '../state/AppSettings';
import { WindowState } from '../state/WindowState';
import { CARD_GAP, CARD_RADIUS, PAGE_PADDING } from './Materials';
import { navTitleBarStyle, TITLE_BAR_H } from './NavStyle';

/**
 * 独立评论页（源 `GalleryCommentsScene` 同形）：全量评论 + 输入框 + 发送。
 * 发评论逻辑从详情页搬迁；详情只留前 3 条展示。
 */
@ComponentV2
export struct CommentsPage {
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  @Local gid: number = 0;
  private token: string = '';
  private data: GalleryDetail | null = null;
  @Local comments: GalleryComment[] = [];
  @Local draft: string = '';
  @Local commentBusy: boolean = false;
  @Local message: string = '加载中…';
  /** 系统安全区（顶部避让 = safeTop + 标题栏高）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  /** 取数单飞（`onReady` 与 `onAppear` 都会触发首载，无锁会并发打两次详情）。 */
  private isLoading: boolean = false;
  /** 评论列表滚动器（标题栏渐变模糊用）。 */
  private scroller: Scroller = new Scroller();

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private async load(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      const detail: GalleryDetail | null =
        await client.getGalleryDetail(site, this.gid, this.token, this.settings.thumbSize);
      this.data = detail;
      if (detail !== null) {
        this.comments = detail.comments;
        this.message = '';
      } else {
        this.message = errorText(null, GalleryDetailParser.lastReason());
      }
    } catch (e) {
      Logger.error('Comments', `load failed gid=${this.gid}: ${e}`);
      this.message = errorText(e as Object);
    }
    this.isLoading = false;
  }

  private async sendComment(): Promise<void> {
    if (this.data === null || this.commentBusy) {
      return;
    }
    const d: GalleryDetail = this.data;
    if (d.apiUid < 0 || d.apiKey.length === 0) {
      this.message = '登录后才能评论';
      return;
    }
    if (this.draft.trim().length === 0) {
      this.message = '先写点内容再发送';
      return;
    }
    this.commentBusy = true;
    try {
      const site: EhSite = this.settings.site;
      const cookies: CookieStore = new CookieStore();
      await cookies.init(this.context());
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      this.comments = await client.postComment(site, d.gid, d.token, this.draft.trim());
      this.draft = '';
      this.message = '';
    } catch (e) {
      Logger.error('Comments', `comment failed gid=${d.gid}: ${e}`);
      this.message = '评论失败，草稿已保留';
    }
    this.commentBusy = false;
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.comments.length === 0 && this.message === '') {
          Text('暂无评论')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding(PAGE_PADDING)
        } else {
          List({ space: CARD_GAP, scroller: this.scroller }) {
            // 顶部避让放进滚动内容（顶部渐变才有效果）。
            ListItem() {
              Column().height(this.windowState.safeTop + TITLE_BAR_H)
            }
            Repeat(this.comments)
              .virtualScroll({ reusable: false })
              .each((ri: RepeatItem<GalleryComment>) => {
                ListItem() {
                  Column({ space: 2 }) {
                    Text(`${ri.item.user} · ${ri.item.time}` +
                      (ri.item.score !== undefined ? ` · ${ri.item.score} 分` : ''))
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .width('100%')
                    Text(ri.item.text)
                      .fontSize(13)
                      .fontColor($r('app.color.text_primary'))
                      .width('100%')
                  }
                  .width('100%')
                  .padding(12)
                  // 每条评论一张卡（与全应用卡片形态一致）。
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(CARD_RADIUS)
                }
                .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
              })
              .key((comment: GalleryComment) => `${comment.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .contentStartOffset(12)
          .contentEndOffset(12)
        }
        Row({ space: 8 }) {
          TextInput({ placeholder: '写下你的评论', text: this.draft })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.draft = value;
            })
            .enabled(!this.commentBusy)
          Button(this.commentBusy ? '发送中…' : '发送')
            .enabled(!this.commentBusy)
            .onClick(() => {
              this.sendComment();
            })
        }
        .width('100%')
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 8, bottom: 4 })
        if (this.message.length > 0) {
          Text(this.message)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .padding(6)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_primary'))
      // 沉浸式布局下内容会铺到手势条后面：底部整体避让安全区，输入框不压小白条。
      .padding({ bottom: this.windowState.safeBottom })
      .onAppear(() => {
        if (this.comments.length === 0) {
          this.load();
        }
      })
    }
    .titleBar({ avoidLayoutSafeArea: true, style: navTitleBarStyle(), content: { title: { mainTitle: '评论' } } })
    .bindToScrollable([this.scroller])
    .onReady((ctx: NavDestinationContext) => {
      const param: DetailParam | undefined = ctx.pathInfo.param as DetailParam | undefined;
      if (param === undefined) {
        this.message = '缺少参数';
        return;
      }
      this.gid = param.gid;
      this.token = param.token;
      this.load();
    })
  }
}
