import { image } from '@kit.ImageKit';
import { PreviewCell } from '../model/PreviewCell';
import { PreviewSpriteCache } from '../service/PreviewSpriteCache';
import { PreviewCropCell } from './PreviewCropCell';

/**
 * 跳页条带里的单格：**由它来读 `cell.url`**，而不是在 `LazyForEach` 的 builder 里直接 `if`。
 *
 * 为什么：`LazyForEach` 建好的 item 在数据到达后不会因为 `onDataChange` 重跑 builder
 * （真机实测：打开时先建的格子 + `cachedCount` 预建的邻居，块数据到达后仍然是灰的，
 * 只有滑进来新建的格子才有图）。`PreviewCell` 是 `@ObservedV2`，这里以 `@Param` 持有它、
 * 在 build 里读 `@Trace` 字段 —— 数据一写进去，组件自己就重绘。
 */
@ComponentV2
export struct JumpStripCell {
  @Require @Param cell: PreviewCell;
  @Require @Param cellW: number;
  @Require @Param cellH: number;
  @Require @Param spriteOf: (cell: PreviewCell) => Promise<image.PixelMap | null>;

  build() {
    if (this.cell.url.length > 0) {
      PreviewCropCell({
        page: this.cell.page,
        w: this.cell.w,
        h: this.cell.h,
        cacheKey: PreviewSpriteCache.keyOf(this.cell.url, this.cell.x, this.cell.y, this.cell.w, this.cell.h),
        fixedH: this.cellH,
        load: () => this.spriteOf(this.cell)
      })
        .width(this.cellW)
    } else {
      // 未取到：同高灰块 + 页码，滚动不跳变，也让用户知道滚到哪了。
      Column({ space: 2 }) {
        Column()
          .width('100%')
          .height(this.cellH)
          .borderRadius(6)
          .backgroundColor($r('app.color.bg_secondary'))
        Text(`${this.cell.page + 1}`)
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
    }
  }
}
