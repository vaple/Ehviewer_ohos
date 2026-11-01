import { TagCandidate } from '../tagdb/TagCandidate';
import { TagDb } from '../tagdb/TagDb';
import { CARD_RADIUS, TOUCH_MIN } from './Materials';

/** 面板一次最多露出的行数（更多候选在面板内部滚动）。 */
const SUGGESTION_MAX_ROWS: number = 6;

/**
 * 搜索框的中文 → 英文标签联想面板（`SearchPage` 的覆盖层；见 design §5.2）。
 *
 * 只占自身高度：面板是「漂在列表上方的一张卡」，不做全屏容器、不铺 `Blank`——
 * 空白区域一旦成为命中目标，就会把下层列表的单击/滑动全吞掉（`ui/AGENTS.md` #21）。
 *
 * 6 行是**视口**上限，不是候选上限：`TagDb.search` 给的 20 条全部喂进来，超出的靠面板内 `Scroll` 滚动，
 * 否则第 7 条以后的候选永远点不到。
 * 视口高度 = 6 × 首行实测高度：行高跟着字号/系统缩放走，写死常量在 1.75 倍字号下会切掉第二行；
 * 只量首行是因为候选行只有「有/无释义」两种形态，同一批里几乎一致，个别高出的行由滚动兜住。
 *
 * `Scroll` 不设固定高度、只用 `constraintSize({ maxHeight })`：内容不足 6 行时它会自适应到内容高度
 * （卡片不会拖出一段空白），超出时才截成视口。
 */
@ComponentV2
export struct TagSuggestionPanel {
  /** 候选（已按相关度排好）。 */
  @Param items: TagCandidate[] = [];
  /**
   * 选中：回传**英文原串**，由页面拼 `ns:"tag$"` 写回输入框。
   * 刻意不给空实现默认值：漏传时宁可当场抛错（点一下就没反应才是最坏的结果）。
   */
  @Event onPick: (ns: string, tag: string) => void;
  /** 首行实测高度（vp）；未量出来前按最小可点高度兜底，避免首帧把 20 行全铺开。 */
  @Local rowHeight: number = TOUCH_MIN;

  @Computed get viewportHeight(): number {
    return SUGGESTION_MAX_ROWS * this.rowHeight;
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.items, (item: TagCandidate, index: number) => {
            Column({ space: 2 }) {
              Row() {
                // 命名空间给中文（`女性 · big breasts`）：用户输入的是中文，先认命名空间再认英文原串。
                Text(`${TagDb.translateNs(item.ns)} · `)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                Text(item.tag)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              // 释义是「这是什么」的补充；多数 tag 没有（约 7 成），没有就整行不画——空行只会把面板撑高。
              if (item.intro.length > 0) {
                Text(item.intro)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
            }
            .width('100%')
            // 行高下限 = 首行实测高度：让所有行至少一样高，
            // 「视口 = 6 × 行高」才同时保证「最多露 6 行」（高出的行只可能更少，不会多出第 7 行）。
            .constraintSize({ minHeight: this.rowHeight })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.onPick(item.ns, item.tag);
            })
            // 只量首行（`index` 来自 `ForEach`）：定标用的样本必须稳定，否则面板会在测高-重布局之间抖动。
            .onAreaChange((_old: Area, now: Area) => {
              if (index !== 0) {
                return;
              }
              const height: Length = now.height;
              if (typeof height !== 'number' || height <= 0 || height === this.rowHeight) {
                return;
              }
              this.rowHeight = height;
            })
          }, (item: TagCandidate) => `${item.ns}:${item.tag}`)
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
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    // 卡片浮在列表缩略图之上：用边框（而不是自绘阴影/半透明遮罩）划出边界，深浅色都跟令牌走。
    .border({ width: 1, color: $r('app.color.divider') })
    .clip(true)
  }
}
