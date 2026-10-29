import { AppStorageV2, PersistenceV2, promptAction } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { DownloadItem, DownloadState } from '../model/DownloadRecord';
import { downloadManager } from '../service/DownloadManager';
import { DownloadDao } from '../db/dao/DownloadDao';
import { formatBytes } from '../common/Bytes';
import { DetailParam } from '../model/DetailParam';
import { CARD_GAP, CARD_RADIUS, PAGE_PADDING } from './Materials';
import { navTitleBarStyle, TITLE_BAR_H } from './NavStyle';
import { WindowState } from '../state/WindowState';
import { AppSettings } from '../state/AppSettings';
import { EhUrl } from '../network/EhUrl';
import { CookieStore } from '../network/CookieStore';
import { RcpHttpClient } from '../network/RcpHttpClient';
import { EhClient } from '../network/EhClient';
import { ImageStore } from '../service/ImageStore';
import { Logger } from '../common/Logger';
import { ReadingProgressStore } from '../state/ReadingProgressStore';

/** 下载列表（我的 → 下载）：封面 / 进度 / 暂停 / 继续 / 删除。点行直接读本地。 */
@ComponentV2
export struct DownloadsPage {
  @Local message: string = '';
  private pageStack: NavPathStack | undefined = undefined;
  private scroller: Scroller = new Scroller();
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  private progress: ReadingProgressStore = PersistenceV2.globalConnect({
    type: ReadingProgressStore,
    key: 'ReadingProgressStore',
    defaultCreator: () => new ReadingProgressStore()
  })!;
  /** 读进度版本（`onShown` 递增）：让 `taskCard` 里的进度文案能跟着从阅读器返回刷新。 */
  @Local progressVersion: number = 0;

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  /** 「读到 X/N 页 · 」前缀（没读过 / 只在第 1 页时为空）。 */
  private readingPrefix(item: DownloadItem): string {
    if (this.progressVersion < 0 || item.pages <= 0) {
      return '';
    }
    const page: number = this.progress.peek(item.gid);
    return page > 0 ? `读到 ${page + 1}/${item.pages} 页 · ` : '';
  }

  private async load(): Promise<void> {
    try {
      await downloadManager.init(this.context());
      await downloadManager.reload();
      this.message = downloadManager.items.length === 0 ? '还没有下载' : '';
      this.loadCovers();
    } catch (e) {
      this.message = '下载列表读取失败';
    }
  }

  /** 补齐封面（带 Cookie/Referer 落盘；单张失败只记日志，列表照常显示）。 */
  private async loadCovers(): Promise<void> {
    const missing: DownloadItem[] = [];
    for (let i = 0; i < downloadManager.items.length; i++) {
      const item: DownloadItem = downloadManager.items[i];
      if (item.thumb.length === 0 && item.thumbUrl.length > 0) {
        missing.push(item);
      }
    }
    if (missing.length === 0) {
      return;
    }
    try {
      const ctx: common.Context = this.context();
      const cookies: CookieStore = new CookieStore();
      await cookies.init(ctx);
      const client: EhClient = new EhClient(new RcpHttpClient(), cookies);
      const store: ImageStore = new ImageStore();
      await store.init(ctx);
      const referer: string = EhUrl.referer(this.settings.site);
      for (let i = 0; i < missing.length; i++) {
        try {
          const uri: string = await store.get(client, missing[i].thumbUrl, referer);
          missing[i].thumb = uri;
          await DownloadDao.setThumb(missing[i].gid, uri);
        } catch (e) {
          Logger.error('Download', `cover load failed gid=${missing[i].gid}: ${e}`);
        }
      }
    } catch (e) {
      Logger.error('Download', `cover batch failed: ${e}`);
    }
  }

  private open(item: DownloadItem): void {
    const param: DetailParam = { gid: item.gid, token: item.token, pages: item.pages };
    this.pageStack?.pushPathByName('阅读', param);
  }

  private confirmRemove(item: DownloadItem): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除下载',
      message: `同时删除已下载的 ${item.donePages} 页？`,
      buttons: [{ text: '再想想', color: '#8C8C8C' }, { text: '删除', color: '#E5484D' }]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        downloadManager.remove(item.gid, true);
      }
    }).catch((_e: object) => {
      // 对话框失败不影响列表
    });
  }

  @Builder
  taskCard(item: DownloadItem) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        // 封面：本地缓存 URI（缺图时占位，不阻塞列表）。
        if (item.thumb.length > 0) {
          Image(item.thumb)
            .width(64)
            .height(84)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.arrow_down_to_line'))
              .fontSize(22)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(64)
          .height(84)
          .justifyContent(FlexAlign.Center)
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.divider') })
          .backgroundColor($r('app.color.bg_primary'))
        }
        Column({ space: 2 }) {
          Text(item.title.length > 0 ? item.title : `gid ${item.gid}`)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(`${this.readingPrefix(item)}${DownloadDao.stateLabel(item.state)} · ` +
            `${item.donePages}/${item.pages} 页 · ` +
            `${DownloadDao.qualityLabel(item.quality)} · ${formatBytes(item.bytes)}`)
            .fontSize(12)
            .fontColor(item.state === DownloadState.FAILED
              ? $r('app.color.danger') : $r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (item.state === DownloadState.RUNNING || item.state === DownloadState.QUEUED) {
          SymbolGlyph($r('sys.symbol.pause'))
            .fontSize(20)
            .fontColor([$r('app.color.text_primary')])
            .padding(12)
            .accessibilityText('暂停下载')
            .onClick(() => {
              downloadManager.pause(item.gid);
            })
        } else if (item.state !== DownloadState.DONE) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(20)
            .fontColor([$r('app.color.brand')])
            .padding(12)
            .accessibilityText('继续下载')
            .onClick(() => {
              downloadManager.resume(item.gid);
            })
        }
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
          .padding(12)
          .accessibilityText('删除下载')
          .onClick(() => {
            this.confirmRemove(item);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (item.state !== DownloadState.DONE && item.pages > 0) {
        Progress({ value: item.donePages, total: item.pages, type: ProgressType.Linear })
          .width('100%')
          .color(item.state === DownloadState.FAILED ? $r('app.color.danger') : $r('app.color.brand'))
      }
      if (item.message.length > 0) {
        Text(item.message)
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
  }

  build() {
    HdsNavDestination() {
      List({ scroller: this.scroller }) {
        ListItem() {
          Column().height(this.windowState.safeTop + TITLE_BAR_H)
        }
        if (downloadManager.items.length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.arrow_down_to_line'))
                .fontSize(40)
                .fontColor([$r('app.color.text_secondary')])
              Text(this.message.length > 0 ? this.message : '还没有下载')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Text('在画廊详情页点下载；内容保存在应用内，不会出现在系统相册。')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding({ top: 80, left: 24, right: 24 })
          }
        }
        Repeat(downloadManager.items)
          .each((ri: RepeatItem<DownloadItem>) => {
            ListItem() {
              this.taskCard(ri.item)
            }
            .margin({ bottom: CARD_GAP })
            .onClick(() => {
              this.open(ri.item);
            })
          })
          .key((item: DownloadItem) => `${item.gid}`)
        ListItem() {
          Column().height(this.windowState.safeBottom + 16)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
      .scrollBar(BarState.Off)
      .backgroundColor($r('app.color.bg_primary'))
      .onAppear(() => {
        this.load();
      })
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      style: navTitleBarStyle(),
      content: { title: { mainTitle: '下载' } }
    })
    .bindToScrollable([this.scroller])
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
    })
    // 从阅读器返回：刷新行内的「读到 X/N」。
    .onShown(() => {
      this.progressVersion += 1;
    })
  }
}
