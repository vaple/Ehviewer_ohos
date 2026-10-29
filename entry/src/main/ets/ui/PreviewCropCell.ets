import { image } from '@kit.ImageKit';
import { Logger } from '../common/Logger';
import { PreviewSpriteCache } from '../service/PreviewSpriteCache';

/**
 * 预览裁剪格（`PreviewSpriteCache` 给成品小图，`Image(PixelMap)` 直显）。
 * `load` 由父注入；就绪才挂 `Image`（`PixelMap` 换实例才刷新，沿官方约束）。
 * 失败灰占位（记日志，不抛）。
 */
@ComponentV2
export struct PreviewCropCell {
  @Require @Param page: number;
  @Require @Param w: number;
  @Require @Param h: number;
  @Require @Param cacheKey: string;
  @Require @Param load: () => Promise<image.PixelMap | null>;
  /** 固定高度（vp）：>0 时按这个高度等高裁切（横向条带用），否则按服务器给的裁剪比例。 */
  @Param fixedH: number = 0;
  @Local ready: boolean = false;
  private pm: image.PixelMap | undefined = undefined;
  /** 代际（disappear 后完成的加载立即归还，不点亮）。 */
  private gen: number = 0;

  build() {
    Column({ space: 2 }) {
      if (this.ready && this.pm !== undefined) {
        if (this.fixedH > 0) {
          Image(this.pm)
            .width('100%')
            .height(this.fixedH)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
            .backgroundColor($r('app.color.bg_secondary'))
        } else {
          Image(this.pm)
            .width('100%')
            .aspectRatio(this.w / this.h)
            .borderRadius(6)
            .backgroundColor($r('app.color.bg_secondary'))
        }
      } else if (this.fixedH > 0) {
        Column()
          .width('100%')
          .height(this.fixedH)
          .borderRadius(6)
          .backgroundColor($r('app.color.bg_secondary'))
      } else {
        Column()
          .width('100%')
          .aspectRatio(this.w / this.h)
          .borderRadius(6)
          .backgroundColor($r('app.color.bg_secondary'))
      }
      Text(`${this.page + 1}`)
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .onAppear(() => {
      if (this.ready) {
        return;
      }
      const g: number = this.gen;
      const key: string = this.cacheKey;
      this.load().then((pm: image.PixelMap | null) => {
        if (pm === null) {
          return;
        }
        if (g !== this.gen) {
          PreviewSpriteCache.release(key);
          return;
        }
        this.pm = pm;
        this.ready = true;
      }).catch((e: object) => {
        Logger.error('Detail', `preview crop load page=${this.page}: ${e}`);
      });
    })
    .onDisAppear(() => {
      this.gen += 1;
      this.pm = undefined;
      this.ready = false;
      PreviewSpriteCache.release(this.cacheKey);
    })
  }
}
