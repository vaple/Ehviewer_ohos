import { CARD_RADIUS, THUMB_RADIUS } from './Materials';
import { SkeletonBlock } from './Skeleton';

/**
 * 首屏骨架行下标。
 *
 * 数量按真机最长的一屏算：行高 383px（113.5vp），2848px 高的屏幕能放 7.4 行 → 取 8 条铺满。
 * 少给会在底部留一截空白（用户实测指出）；多给的部分只是超出屏幕、可滚动，没有副作用。
 *
 * 为什么不写 `Repeat(8)`：`Repeat` 对「数字种子」的语义是**重复次数**，`each` 里拿不到序号；
 * 给显式数组才能稳定生成 `sk-0…sk-7` 这批 key（与真行的 `${gid}` key 不冲突）。
 */
export const SKELETON_ROW_INDICES: number[] = [0, 1, 2, 3, 4, 5, 6, 7];

/**
 * 列表首屏骨架行（六个列表共用：首页 / 搜索 / 历史 / 排行 / 订阅 / 收藏）。
 *
 * 为什么要有它、而不是各页自己画个居中 `LoadingProgress`：
 * - 转圈占位在数据到达时会让整屏内容「跳」一下（转圈换成 5 行卡片）；骨架行与 `GalleryRow` 同尺寸，
 *   版式零跳变；
 * - 更关键的是**不要在 `List` 之外再放一个 `layoutWeight(1)` 的占位块**：那会让「列表」和「加载中」
 *   在同一列里各占一半高度（收藏页踩过，`ui/AGENTS.md` #79）。骨架行天然在 `List` 里，没有这个形状。
 *
 * 尺寸全部对齐 `GalleryRow`：84×84 封面 + 三行文字块（标题两行 + meta），出图后不重排。
 */
@ComponentV2
export struct GalleryRowSkeleton {
  build() {
    Row({ space: 12 }) {
      SkeletonBlock({ w: 84, h: 84, corner: THUMB_RADIUS })
      Column({ space: 8 }) {
        SkeletonBlock({ w: '86%', h: 16, corner: 4 })
        SkeletonBlock({ w: '54%', h: 16, corner: 4 })
        SkeletonBlock({ w: '40%', h: 12, corner: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
  }
}
