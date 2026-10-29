import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppStorageV2, promptAction, SubHeaderV2, SubHeaderV2Title } from '@kit.ArkUI';
import { Filter } from '../model/Filter';
import { qualifyTag } from '../search/SearchQuery';
import { FilterDao } from '../db/dao/FilterDao';
import { DbHelper } from '../db/DbHelper';
import { Logger } from '../common/Logger';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { CARD_GAP, CARD_RADIUS, PAGE_PADDING } from './Materials';
import { navTitleBarStyle, TITLE_BAR_H } from './NavStyle';
import { WindowState } from '../state/WindowState';

/** 语法速查（EHWiki Gallery Searching 原文语义）。 */
interface SyntaxItem {
  token: string;
  desc: string;
}

const SYNTAX: SyntaxItem[] = [
  { token: '-tag', desc: '排除某标签（如 -other:ai generated）' },
  { token: '~tag', desc: 'OR：命中任一即可' },
  { token: '$', desc: '后缀：精确标签（f:wolf$ 不会命中 wolf girl）' },
  { token: 'weak:tag', desc: '弱标签匹配（1–9 power），不可用于排除' },
  { token: 'title: / uploader:', desc: '只在标题 / 上传者里搜' }
];

/**
 * 搜索排除（不再本地过滤）：
 * 这里的每条规则在**每次关键词搜索**时自动拼成 `-…` 查询条件（服务端排除），
 * 不会隐藏列表内容；站点级硬/软屏蔽引导到官方 My Tags / 站点设置。
 */
@ComponentV2
export struct BlockListPage {
  @Local rules: Filter[] = [];
  @Local draft: string = '';
  @Local message: string = '加载中…';
  /** 语法速查默认折叠（低频，避免术语刷屏）。 */
  @Local syntaxExpanded: boolean = false;
  private scroller: Scroller = new Scroller();
  private pageStack: NavPathStack | undefined = undefined;
  /** 系统安全区（顶部避让 = safeTop + 标题栏高；底部手势条同样运行时读）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private async reload(): Promise<void> {
    try {
      await DbHelper.init(this.context());
      this.rules = await FilterDao.queryAll();
      this.message = this.rules.length === 0 ? '还没有排除规则' : '';
    } catch (e) {
      Logger.error('Block', `rules load failed: ${e}`);
      this.message = '规则加载失败';
      promptAction.showToast({ message: '规则加载失败，请重试' });
    }
  }

  private async addRule(): Promise<void> {
    const raw: string = this.draft.trim();
    if (raw.length === 0) {
      promptAction.showToast({ message: '先输入要排除的内容' });
      return;
    }
    // 统一成查询词（含空格的值自动加引号）。
    const text: string = qualifyTag(raw);
    try {
      await DbHelper.init(this.context());
      await FilterDao.add({ id: 0, mode: 0, text: text, enable: true });
      this.draft = '';
      await this.reload();
    } catch (e) {
      Logger.error('Block', `rule add failed: ${e}`);
      promptAction.showToast({ message: '添加失败，请重试' });
    }
  }

  private async toggleRule(rule: Filter): Promise<void> {
    try {
      await DbHelper.init(this.context());
      await FilterDao.setEnabled(rule.id, !rule.enable);
      await this.reload();
    } catch (e) {
      Logger.error('Block', `rule toggle failed id=${rule.id}: ${e}`);
      promptAction.showToast({ message: '操作失败，请重试' });
    }
  }

  private confirmDelete(rule: Filter): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除排除规则',
      message: `确定删除「${rule.text}」吗？`,
      buttons: [{ text: '再想想', color: '#8C8C8C' }, { text: '确定', color: '#3D6BE5' }]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.deleteRule(rule);
      }
    }).catch((_e: object) => {
      // 对话框自身失败不影响列表
    });
  }

  private async deleteRule(rule: Filter): Promise<void> {
    try {
      await DbHelper.init(this.context());
      await FilterDao.delete(rule.id);
      await this.reload();
    } catch (e) {
      Logger.error('Block', `rule delete failed id=${rule.id}: ${e}`);
      promptAction.showToast({ message: '删除失败，请重试' });
    }
  }

  private async copySyntax(token: string): Promise<void> {
    try {
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, token);
      await pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: `已复制 ${token}` });
    } catch (e) {
      Logger.error('Block', `copy syntax failed: ${e}`);
      promptAction.showToast({ message: '复制失败，请重试' });
    }
  }

  /** 由前缀推断类型（展示用，不需要用户先选模式）。 */
  private typeLabel(text: string): string {
    if (text.startsWith('uploader:')) {
      return '上传者';
    }
    if (text.startsWith('title:')) {
      return '标题';
    }
    return text.indexOf(':') >= 0 ? '标签' : '关键词';
  }

  /** 主动作：添加一条排除条件（标签 / 上传者 / 标题用官方前缀区分）。 */
  @Builder
  addCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: '要排除的内容', text: this.draft })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.draft = value;
          })
          .onSubmit(() => {
            this.addRule();
          })
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(20)
          .fontColor([$r('app.color.brand')])
          .padding(12)
          .accessibilityText('添加排除规则')
          .onClick(() => {
            this.addRule();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text('标签 other:ai generated\n上传者 uploader:名字 · 标题 title:关键词')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: CARD_GAP })
  }

  /** 规则列表：一张卡内多行，行间分隔线（不再一行一张卡，避免"粘连"与宽度漂移）。 */
  @Builder
  rulesCard() {
    Column() {
      if (this.rules.length === 0) {
        Text(this.message === '还没有排除规则' ? '还没有规则，先在上方添加一条' : this.message)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 14, bottom: 14 })
      } else {
        Repeat(this.rules)
          .each((ri: RepeatItem<Filter>) => {
            Column() {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(ri.item.text)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(this.typeLabel(ri.item.text))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: ri.item.enable })
                  .onChange((on: boolean) => {
                    if (on !== ri.item.enable) {
                      this.toggleRule(ri.item);
                    }
                  })
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(18)
                  .fontColor([$r('app.color.text_secondary')])
                  .padding(12)
                  .accessibilityText('删除排除规则')
                  .onClick(() => {
                    this.confirmDelete(ri.item);
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ top: 10, bottom: 10 })
              if (ri.index < this.rules.length - 1) {
                Divider()
                  .color($r('app.color.divider'))
                  .strokeWidth(0.5)
              }
            }
            .width('100%')
          })
          .key((rule: Filter) => `${rule.id}:${rule.enable}`)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: CARD_GAP })
  }

  /** 站点级屏蔽：整类标签 / 语言 / 上传者由官方页面处理（本页规则只影响搜索查询）。 */
  @Builder
  siteCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')])
      Column({ space: 2 }) {
        Text('My Tags / 站点设置')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('整类标签 / 语言 / 上传者（设置页）')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([$r('app.color.text_secondary')])
        .padding(12)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: CARD_GAP })
    .onClick(() => {
      this.pageStack?.pushPathByName('设置', undefined);
    })
  }

  /** 语法速查（默认折叠；点一条复制，供高级用户手写查询）。 */
  @Builder
  syntaxCard() {
    Column({ space: 2 }) {
      Row() {
        Text('展开语法速查')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Blank()
        SymbolGlyph($r(this.syntaxExpanded ? 'sys.symbol.chevron_up' : 'sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
          .padding(12)
      }
      .width('100%')
      .onClick(() => {
        this.syntaxExpanded = !this.syntaxExpanded;
      })
      if (this.syntaxExpanded) {
        Repeat(SYNTAX)
          .each((si: RepeatItem<SyntaxItem>) => {
            Column({ space: 2 }) {
              Text(si.item.token)
                .fontSize(12)
                .fontColor($r('app.color.brand'))
                .width('100%')
              Text(si.item.desc)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
            .onClick(() => {
              this.copySyntax(si.item.token);
            })
          })
          .key((item: SyntaxItem) => item.token)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: CARD_GAP })
  }

  build() {
    HdsNavDestination() {
      // 整页一个 List：说明 / 添加 / 规则 / 站点级 / 语法一起随内容滚到标题栏下（渐变才有内容穿过）。
      List({ scroller: this.scroller }) {
        ListItem() {
          Column().height(this.windowState.safeTop + TITLE_BAR_H)
        }
        ListItem() {
          Text('每次搜索时自动带上这些排除条件')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 8 })
            .margin({ bottom: CARD_GAP })
        }
        ListItem() {
          SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '排除规则' }) })
        }
        ListItem() {
          this.addCard()
        }
        ListItem() {
          this.rulesCard()
        }
        ListItem() {
          SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '站点级屏蔽' }) })
        }
        ListItem() {
          this.siteCard()
        }
        ListItem() {
          SubHeaderV2({ title: new SubHeaderV2Title({ primaryTitle: '搜索语法' }) })
        }
        ListItem() {
          this.syntaxCard()
        }
        ListItem() {
          Column().height(this.windowState.safeBottom + CARD_GAP)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
      .scrollBar(BarState.Off)
      .backgroundColor($r('app.color.bg_primary'))
      .onAppear(() => {
        this.reload();
      })
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      style: navTitleBarStyle(),
      content: { title: { mainTitle: '搜索排除' } }
    })
    .bindToScrollable([this.scroller])
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack;
    })
  }
}
