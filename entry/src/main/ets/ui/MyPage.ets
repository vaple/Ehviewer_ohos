import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { HdsListItemCard, PrefixIcon, SuffixArrow, SuffixBadgeAndArrow } from '@kit.UIDesignKit';
import { SessionState } from '../state/SessionState';
import { AppSettings } from '../state/AppSettings';
import { WindowState } from '../state/WindowState';
import { CARD_GAP, TAB_BAR_CLEARANCE } from './Materials';
import { TITLE_BAR_H } from './NavStyle';
import { EhSite } from '../network/EhUrl';
import { VERSION_NAME } from 'BuildProfile';
import { UpdateState, hasUpdate, updateState } from '../state/UpdateState';

/** “我的”入口项（图标 + 标题 + 路由名）。 */
interface MyEntry {
  icon: ResourceStr;
  title: string;
  name: string;
}

const MY_ENTRIES: MyEntry[] = [
  { icon: $r('sys.symbol.star'), title: '收藏', name: '收藏' },
  { icon: $r('sys.symbol.clock'), title: '历史', name: '历史' },
  { icon: $r('sys.symbol.arrow_down_to_line'), title: '下载', name: '下载' },
  { icon: $r('sys.symbol.eye_slash'), title: '搜索排除', name: '屏蔽' },
  { icon: $r('sys.symbol.gearshape'), title: '设置', name: '设置' }
];

/**
 * “我的”页（tab 根）：身份卡（HdsListItemCard）+ 四入口（收藏/历史/屏蔽/设置）。
 * 点行 push 对应页（push 栈由父级 `AppShell` 经 `@Param pageStack` 传入）。
 */
@ComponentV2
export struct MyPage {
  @Require @Param pageStack: NavPathStack;
  /** 外部滚动联动（`AppShell` 按 tab 持有，标题栏渐进模糊用；`Scroll` 绑定）。 */
  @Require @Param scroller: Scroller;
  private session: SessionState = AppStorageV2.connect(SessionState, () => new SessionState())!;
  /** 系统安全区（顶部避让 = safeTop + 标题栏高 + 8 呼吸）。 */
  private windowState: WindowState = AppStorageV2.connect(WindowState, () => new WindowState())!;
  private settings: AppSettings = PersistenceV2.globalConnect({
    type: AppSettings,
    key: 'AppSettings9',
    defaultCreator: () => new AppSettings()
  })!;
  /** 更新检查结果（「设置」入口红点读它）。 */
  private updateStateRef: UpdateState = updateState();

  private entries: MyEntry[] = MY_ENTRIES;

  build() {
    Scroll(this.scroller) {
      Column({ space: CARD_GAP }) {
        // 顶部留白：给标题栏让位（`Blank` 在 `Scroll` 内是弹性占位，会撑出多余空白 → 用固定高 Column）。
        Column().height(this.windowState.safeTop + TITLE_BAR_H + 8)
        HdsListItemCard({
          prefixItem: new PrefixIcon({
            iconValue: { symbol: $r('sys.symbol.person') }
          }),
          textItem: {
            primaryText: { text: this.session.loggedIn ? '已登录' : '未登录' },
            secondaryText: {
              text: this.session.loggedIn
                ? (this.settings.site === EhSite.EX ? 'ExHentai' : 'E-Hentai')
                : '点此去设置页登录'
            }
          },
          onClick: () => {
            this.pageStack.pushPath({ name: '设置' });
          }
        })
        Repeat(this.entries)
          .each((ri: RepeatItem<MyEntry>) => {
            HdsListItemCard({
              prefixItem: new PrefixIcon({
                iconValue: { symbol: ri.item.icon }
              }),
              textItem: {
                primaryText: { text: ri.item.title }
              },
              suffixItem: (ri.item.name === '设置' && hasUpdate(this.updateStateRef, VERSION_NAME))
                ? new SuffixBadgeAndArrow({ badgeValue: -1 }, { color: $r('app.color.danger') })
                : new SuffixArrow({ color: $r('app.color.text_secondary') }),
              onClick: () => {
                this.pageStack.pushPath({ name: ri.item.name });
              }
            })
          })
          .key((item: MyEntry) => item.name)
      }
      .width('100%')
      .padding({ bottom: this.windowState.safeBottom + TAB_BAR_CLEARANCE })
    }
    .width('100%')
    .height('100%')
    // 内容高度小于视口时靠顶排（默认垂直居中会吞掉顶部给标题栏的留白）。
    .align(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor($r('app.color.bg_primary'))
    .scrollBar(BarState.Off)
  }
}
