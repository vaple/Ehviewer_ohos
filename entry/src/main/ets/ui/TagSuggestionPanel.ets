import { TagCandidate } from '../tagdb/TagCandidate';
import { TagDb } from '../tagdb/TagDb';
import { CARD_RADIUS, TOUCH_MIN } from './Materials';

/** 面板一次最多露出的行数（更多候选在面板内部滚动）。 */
const SUGGESTION_MAX_ROWS: number = 6;
/** 视口余量（vp）：抵消「实测行高 × 行数」与滚动容器边界的舍入差，避免最后一行被切半截。 */
const SUGGESTION_VIEWPORT_SLACK: number = 8;

/**
 * 搜索框的中文 → 英文标签联想面板（`SearchPage` 的覆盖层；见 design §5.2）。
 *
 * 只占自身高度：面板是「漂在列表上方的一张卡」，不做全屏容器、不铺 `Blank`——
 * 空白区域一旦成为命中目标，就会把下层列表的单击/滑动全吞掉（`ui/AGENTS.md` #21）。
 *
 * 6 行是**视口**上限，不是候选上限：`TagDb.search` 给的 20 条全部喂进来，超出的靠面板内 `Scroll` 滚动，
 * 否则第 7 条以后的候选永远点不到。
 * 视口高度 = 6 × 视口内实测的**最高**行：行高跟着字号/系统缩放走，写死常量在 1.75 倍字号下会切掉第二行；
 * 取最大值而不是首行，是因为候选行有「有/无释义」两种形态——首行恰好没释义时，按它定标会把第 6 行裁掉一截。
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
  /** 视口内实测的**最高**行（vp）；未量出来前按最小可点高度兜底，避免首帧把 20 行全铺开。 */
  @Local rowHeight: number = TOUCH_MIN;

  /**
   * 视口高度 = 6 行 + 一点余量。
   *
   * 余量不是随手加的：行高是实测的分数 vp（如 44.2857），乘以 6 之后与滚动容器边界有舍入差，
   * 不留余量时第 6 行的第二行文字会被切掉半截（模拟器截图实证）。多给 8vp 的代价是
   * 第 7 行可能露出一点点——反倒是个"还能往下滚"的提示。
   */
  @Computed get viewportHeight(): number {
    return SUGGESTION_MAX_ROWS * this.rowHeight + SUGGESTION_VIEWPORT_SLACK;
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.items, (item: TagCandidate, index: number) => {
            Column({ space: 2 }) {
              Row({ space: 8 }) {
                // 主标题给**中文**（`女性:巨乳`）：用户输入的就是中文，这一列必须先对上。
                Text(`${TagDb.translateNs(item.ns)}:${item.name}`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                // 副标题是**即将插入的原文**（`female:big breasts`）：用站点自己的冒号写法，
                // 让"点下去会写进什么"一眼可见。译名与原 tag 相同（拉丁名、没有译名）时整段不画，
                // 否则会变成 `艺术家:Hige  artist:Hige` 这种重复。
                if (item.name !== item.tag) {
                  Text(`${item.ns}:${item.tag}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
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
            // 行高下限 = 视口内实测的最高一行：让所有行一样高，
            // 「视口 = 6 × 行高」才同时保证「最多露 6 行」且**不裁行**。
            // 不能只用首行定标：首行没释义时比后面的行矮，第 6 行会被裁掉一截（真机截图踩过）。
            .constraintSize({ minHeight: this.rowHeight })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.onPick(item.ns, item.tag);
            })
            // 只在能进视口的前几行里取**最大值**（`index` 来自 `ForEach`）：
            // 行高只有「有/无释义」两种形态，取 max 后所有行被 `minHeight` 拉齐，再没有可变的样本，
            // 所以不会出现测高↔重布局的抖动（单调递增、一次收敛）。
            .onAreaChange((_old: Area, now: Area) => {
              if (index >= SUGGESTION_MAX_ROWS) {
                return;
              }
              const height: Length = now.height;
              if (typeof height !== 'number' || height <= 0) {
                return;
              }
              // 只往大里调：一旦拉齐就不会再变，避免"测高 → 重布局 → 又测出别的值"的来回。
              if (height > this.rowHeight) {
                this.rowHeight = height;
              }
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
    // 半透明磨砂（与搜索历史面板同一套）：内容区自绘浮层拿不到系统材质，只能用官方模糊；
    // 不要叠不透明底色，那会把模糊盖死。
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .borderRadius(CARD_RADIUS)
    // 卡片浮在列表缩略图之上：用边框（而不是自绘阴影/半透明遮罩）划出边界，深浅色都跟令牌走。
    .border({ width: 1, color: $r('app.color.divider') })
    .clip(true)
  }
}
