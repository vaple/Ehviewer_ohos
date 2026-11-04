import { QuickSearch } from '../model/QuickSearch';
import { quickSearchSummary } from '../search/QuickSearchQuery';
import { CARD_RADIUS, TOUCH_MIN } from './Materials';

/** 面板一次最多露出的行数（更多历史在面板内部滚动）。 */
const HISTORY_MAX_ROWS: number = 6;
/** 视口余量（vp）：抵消「实测行高 × 行数」与滚动容器边界的舍入差，避免最后一行被切半截。 */
const HISTORY_VIEWPORT_SLACK: number = 8;

/**
 * 搜索框聚焦（草稿为空）时浮出的「最近搜索」面板。
 *
 * 与 `TagSuggestionPanel` 同一层、同一套布局纪律（`SearchPage` 的覆盖层）：
 * 只占自身高度、不铺满（否则会吞掉下层列表的手势，`ui/AGENTS.md` #21）；
 * 行高实测取最大值、`constraintSize({ maxHeight })` 而不是写死高度（字号/系统缩放会变）。
 *
 * 行样式与快搜一致（主标题 = 最终 `f_search` 主体，副标题 = 条件摘要），
 * 差别只在容器：这里是浮层，所以删除用行尾 `×` 而不是左滑。
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
              // 点文字才重跑；`×` 是删除，两个热区必须分开，别让删一条变成搜一次。
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

      // 清空入口固定在最后一行，不参与滚动（否则历史一多就再也点不到）。
      Row() {
        Text('清空搜索历史')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height(TOUCH_MIN)
      .justifyContent(FlexAlign.Center)
      .border({ width: { top: 1 }, color: $r('app.color.divider') })
      .onClick(() => {
        this.onClear();
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    // 卡片浮在列表缩略图之上：用边框（而不是自绘阴影/半透明遮罩）划出边界，深浅色都跟令牌走。
    .border({ width: 1, color: $r('app.color.divider') })
    .clip(true)
  }
}
