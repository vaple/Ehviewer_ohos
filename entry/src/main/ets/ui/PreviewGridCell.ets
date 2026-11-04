import { image } from '@kit.ImageKit';
import { PreviewCell } from '../model/PreviewCell';
import { PreviewSpriteCache } from '../service/PreviewSpriteCache';
import { PreviewCropCell } from './PreviewCropCell';

/**
 * 详情页预览网格的单格。
 *
 * 为什么由它读 `cell.url`：`LazyForEach` 建好的行不会因数据到达重跑 builder
 * （`ui/AGENTS.md` #65）。`PreviewCell` 是 `@ObservedV2`，这里以 `@Param` 持有它、在 build 里读
 * `@Trace` 字段 —— 块数据一写进去，这一格自己从「页码灰块」切成真图。
 */
@ComponentV2
export struct PreviewGridCell {
  @Require @Param cell: PreviewCell;
  /** 未取到裁剪矩形时的占位宽高比（画廊级，取自首块首格；与真图同比例，行高不会在数据到达时跳）。 */
  @Param aspect: number = 200 / 137;
  @Require @Param spriteOf: (cell: PreviewCell) => Promise<image.PixelMap | null>;

  build() {
    if (this.cell.url.length > 0) {
      PreviewCropCell({
        page: this.cell.page,
        w: this.cell.w,
        h: this.cell.h,
        cacheKey: PreviewSpriteCache.keyOf(this.cell.url, this.cell.x, this.cell.y, this.cell.w, this.cell.h),
        load: () => this.spriteOf(this.cell)
      })
        .width('100%')
    } else {
      Column({ space: 2 }) {
        Column()
          .width('100%')
          .aspectRatio(this.aspect)
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
