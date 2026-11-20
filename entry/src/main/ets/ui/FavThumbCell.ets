import { Logger } from '../common/Logger';
import { GalleryRowItem } from './GalleryRow';
import { SkeletonBlock } from './Skeleton';
import { THUMB_RADIUS } from './Materials';

/** 收藏行 A 区缩略图边长（vp）。方图 + `Cover`：卡片行高固定，不能靠图片撑高。 */
const FAV_THUMB_SIZE: number = 56;

/**
 * 收藏列表 A 区的缩略图格。
 *
 * 为什么必须是一个**独立组件**、并且自己读 `item.thumb`：
 * `HdsListItem` 的 `hdsListItemCard` 是构造时就固定下来的 options 快照，`LazyForEach` 建好的行
 * 也不会因为数据到达重跑 builder（`ui/AGENTS.md` #65 记录的同一类坑，详情预览格踩过）。
 * 若把「有图 / 没图」写在页面的 options 里（`thumb.length > 0 ? PrefixImage : undefined`），
 * 图到得再晚也不会重算 —— 表现为「缺图的行永远是空的」。
 *
 * 骨架：`SkeletonBlock`（官方流光占位，见 `ui/Skeleton.ets`）。占位与真图**同尺寸**，
 * 所以文字列的宽度从第一帧起就是最终宽度，不会再出现「文字铺满整行、图到了才缩回去」。
 */
@ComponentV2
export struct FavThumbCell {
  @Require @Param item: GalleryRowItem;
  /** 取图（页面注入；失败抛给这里，由这里落地成可重试的失败态）。 */
  @Require @Param load: (item: GalleryRowItem) => Promise<string>;
  @Local failed: boolean = false;
  /** 代际：离场/复用后到达的结果直接丢弃（不要把图写回已经被别的行用着的对象）。 */
  private gen: number = 0;

  private fetch(): void {
    const g: number = this.gen;
    this.load(this.item).then((uri: string) => {
      if (g !== this.gen) {
        return;
      }
      if (uri.length === 0) {
        // 空串的含义是「站点没给缩略图」或「还没登录」——都不是失败，别转成重试图标。
        return;
      }
      // `thumb` 是 `@Trace`：写进去这一格自己就切成真图，不依赖父级重跑 options。
      this.item.thumb = uri;
    }).catch((e: object) => {
      Logger.error('Fav', `thumb load failed gid=${this.item.gid}: ${e}`);
      if (g === this.gen) {
        this.failed = true;
      }
    });
  }

  build() {
    Column() {
      if (this.item.thumb.length > 0) {
        Image(this.item.thumb)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else if (this.item.thumbUrl.length === 0) {
        // 站点这一行本来就没给缩略图：不转骨架、也不给重试（重试也永远拿不到），只留一块同尺寸静色。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.bg_primary'))
      } else if (this.failed) {
        Column() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(20)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.failed = false;
          this.fetch();
        })
      } else {
        SkeletonBlock({ h: '100%', corner: THUMB_RADIUS })
      }
    }
    .width(FAV_THUMB_SIZE)
    .height(FAV_THUMB_SIZE)
    .borderRadius(THUMB_RADIUS)
    .clip(true)
    .onAppear(() => {
      if (this.item.thumb.length === 0 && !this.failed && this.item.thumbUrl.length > 0) {
        this.fetch();
      }
    })
    .onDisAppear(() => {
      this.gen += 1;
    })
  }
}
