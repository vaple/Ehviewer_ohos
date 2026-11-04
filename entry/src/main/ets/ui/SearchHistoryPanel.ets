import { QuickSearch } from '../model/QuickSearch';
import { quickSearchSummary } from '../search/QuickSearchQuery';
import { CARD_RADIUS, TOUCH_MIN } from './Materials';

/** 面板一次最多露出的行数（更多历史在面板内部滚动）。 */
const HISTORY_MAX_ROWS: number = 5;
/** 视口余量（vp）：抵消「实测行高 × 行数」与滚动容器边界的舍入差，避免最后一行被切半截。 */
const HISTORY_VIEWPORT_SLACK: number = 8;
/** 头部行高度（vp）：标题 + 清空按钮，固定不滚。 */
const HEADER_H: number = 44;

/**
 * 搜索框聚焦（草稿为空）时浮出的「最近搜索」面板。
 *
 * 与 `TagSuggestionPanel` 同一层、同一套布局纪律（`SearchPage` 的覆盖层）：
 * 只占自身高度、不铺满（否则会吞掉下层列表的手势，`ui/AGENTS.md` #21）；
 * 行高实测取最大值、`constraintSize({ maxHeight })` 而不是写死高度（字号/系统缩放会变）。
 *
 * 材质：内容区的自绘浮层拿不到系统材质（`Materials.ets`），只能走官方 `backgroundBlurStyle`。
 * 磨砂是这里的关键——不加模糊时它会和底下的画廊卡片同色同圆角，看起来像两块纸叠在一起；
 * 注意**不能**再叠不透明底色，那会把模糊整块盖死。
 *
 * 清空历史固定在**头部**：放底部时，键盘一弹高就会把这一行压在键盘下面，
 * 而收键盘又会让输入框失焦、面板跟着收起——那会让清空永远点不到。
 */
@ComponentV2
export struct SearchHistoryPanel {
  /** 历史记录（新的在前）。 */
  @Param items: QuickSearch[] = [];
  @Event onRun: (item: QuickSearch) => void;
  @Event onDelete: (item: QuickSearch) => void;
  @Event onClear: () => void;

  /** 视口内实测的**最高**行（vp）；未量出来前按最小可点高度兜底。 */
  @Local rowHeight: number = TOUCH_MIN;

  @Computed get viewportHeight(): number {
    return HISTORY_MAX_ROWS * this.rowHeight + HISTORY_VIEWPORT_SLACK;
  }

  build() {
    Column() {
      // 头部：标题 + 清空（垃圾桶）。固定不滚，键盘再高也压不到。
      Row() {
        Text('最近搜索')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
          .width(TOUCH_MIN)
          .height(TOUCH_MIN)
          .id('history-clear')
          .accessibilityText('清空搜索历史')
          .onClick(() => {
            this.onClear();
          })
      }
      .width('100%')
      .height(HEADER_H)
      .padding({ left: 12 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          ForEach(this.items, (item: QuickSearch, index: number) => {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(item.keyword)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                if (quickSearchSummary(item).length > 0) {
                  Text(quickSearchSummary(item))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              // 点文字才重跑；`×` 是删除，两个热区必须分开，别让"删一条"变成"搜一次"。
              .onClick(() => {
                this.onRun(item);
              })
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(14)
                .fontColor([$r('app.color.text_secondary')])
                .width(TOUCH_MIN)
                .height(TOUCH_MIN)
                .accessibilityText('删除这条历史')
                .onClick(() => {
                  this.onDelete(item);
                })
            }
            .width('100%')
            .constraintSize({ minHeight: this.rowHeight })
            .alignItems(VerticalAlign.Center)
            .padding({ left: 12, right: 4 })
            .id(`history-${item.id}`)
            // 行分隔：没有分隔线时几行文字会连成一块（深色下尤其明显）。
            .border({
              width: { bottom: index < this.items.length - 1 ? 1 : 0 },
              color: $r('app.color.divider')
            })
            .onAreaChange((_old: Area, now: Area) => {
              if (index >= HISTORY_MAX_ROWS) {
                return;
              }
              const height: Length = now.height;
              if (typeof height !== 'number' || height <= 0) {
                return;
              }
              // 只往大里调：行高拉齐后不再变，避免"测高 → 重布局 → 又测出别的值"的来回。
              if (height > this.rowHeight) {
                this.rowHeight = height;
              }
            })
          }, (item: QuickSearch) => `${item.id}`)
        }
        .width('100%')
      }
      .width('100%')
      .scrollBar(BarState.Off)
      // 内容比视口矮时不要居中：卡片必须从第一行开始贴顶（官方 FAQ `faqs-arkui-725`）。
      .align(Alignment.Top)
      .constraintSize({ maxHeight: this.viewportHeight })
    }
    .width('100%')
    // 半透明磨砂：压在画廊缩略图上仍能读，又能和底下的实色卡片分出层次。
    // 不要再写不透明 `backgroundColor`（会把模糊整块盖死）。
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .borderRadius(CARD_RADIUS)
    .border({ width: 1, color: $r('app.color.divider') })
    .clip(true)
  }
}
