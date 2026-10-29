import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { EhSite, EhUrl } from '../network/EhUrl';
import { EhClient } from '../network/EhClient';
import { ImageStore } from '../service/ImageStore';
import { CATEGORY_UNKNOWN } from '../parser/ParserUtils';
import { catColor, catLabel } from './CategoryStyle';
import { CARD_RADIUS, THUMB_RADIUS } from './Materials';
import { DetailParam, DetailPreview } from '../model/DetailParam';

/**
 * 画廊列表行（列表页与搜索页共用）。
 * 缩略图就绪时只改该项的 `@Trace thumb`（不再整表重赋）。
 * `thumbUrl` 是远端地址（取图用），`thumb` 是落盘后的本地沙箱 URI（`Image` 渲染用）。
 */
@ObservedV2
export class GalleryRowItem {
  gid: number = 0;
  token: string = '';
  title: string = '';
  uploader: string = '';
  thumbUrl: string = '';
  category: number = CATEGORY_UNKNOWN;
  rating: number = 0;
  posted: string = '';
  simpleLanguage: string = '';
  /** 总页数（`GalleryInfo.pages`；`<=0` 不展示）。 */
  pages: number = 0;
  @Trace thumb: string = '';
}

/** 第一 meta 行（评分 · 语言 · 页数；空段跳过，`pages<=0` 不显示）。纯函数，行为即断言。 */
export function rowLine1(item: GalleryRowItem): string {
  const parts: string[] = [];
  if (item.rating > 0) {
    parts.push(`★${item.rating}`);
  }
  if (item.simpleLanguage.length > 0) {
    parts.push(item.simpleLanguage);
  }
  if (item.pages > 0) {
    parts.push(`${item.pages}P`);
  }
  return parts.join(' · ');
}

/** 第二 meta 行（上传者 · 日期；空段跳过）。纯函数，行为即断言。 */
export function rowLine2(item: GalleryRowItem): string {
  const parts: string[] = [];
  if (item.uploader.length > 0) {
    parts.push(item.uploader);
  }
  if (item.posted.length > 0) {
    parts.push(item.posted);
  }
  return parts.join(' · ');
}

/** 该项是否缺缩略图（有远端、无本地）。 */
export function thumbPending(item: GalleryRowItem): boolean {
  return item.thumbUrl.length > 0 && item.thumb.length === 0;
}

/** 列表行 → 详情快照（纯函数；详情页首帧标题/封面/页数不等网络）。 */
export function toDetailPreview(item: GalleryRowItem): DetailPreview {
  return {
    title: item.title,
    category: item.category,
    uploader: item.uploader,
    rating: item.rating,
    pages: item.pages,
    thumb: item.thumb,
    thumbUrl: item.thumbUrl
  };
}

/** 共享元素 id（列表缩略图 ↔ 详情封面；同一 gid 同名）。 */
export function galleryGeometryId(gid: number): string {
  return `gallery-${gid}`;
}

/**
 * 列表 → 详情转场打开（官方共享元素三步中的后两步：`animateTo` 包裹路由 + 关闭系统默认转场）。
 * 重复点击保护：栈顶已是详情则忽略（`pushPathByName` 同步入栈，连点第二下会被这里挡住）。
 */
export function pushGalleryDetail(ctx: UIContext, stack: NavPathStack | undefined,
  item: GalleryRowItem): void {
  if (stack === undefined) {
    return;
  }
  const names: string[] = stack.getAllPathName();
  if (names.length > 0 && names[names.length - 1] === '详情') {
    return;
  }
  const param: DetailParam = { gid: item.gid, token: item.token, preview: toDetailPreview(item) };
  ctx.animateTo({ duration: 350, curve: Curve.EaseInOut }, () => {
    stack.pushPathByName('详情', param, false);
  });
}

/**
 * 为缺缩略图的条目补齐（带 Cookie/Referer 落盘后就地更新该项）。
 * 单张失败忽略（下次加载重试）；调用方 fire-and-forget 即可。
 */
export async function loadMissingThumbs(context: common.Context, client: EhClient,
  site: EhSite, items: GalleryRowItem[]): Promise<void> {
  const store: ImageStore = new ImageStore();
  await store.init(context);
  const referer: string = EhUrl.referer(site);
  const tasks: Promise<void>[] = [];
  for (let i = 0; i < items.length; i++) {
    if (thumbPending(items[i])) {
      tasks.push(loadThumb(store, client, items[i], referer));
    }
  }
  await Promise.all(tasks);
}

async function loadThumb(store: ImageStore, client: EhClient,
  item: GalleryRowItem, referer: string): Promise<void> {
  try {
    item.thumb = await store.get(client, item.thumbUrl, referer);
  } catch (e) {
    // 单张失败忽略（下次加载重试）
  }
}

/** 列表行（卡片形态）。`@ReusableV2`：组件状态只来自 `@Param`，复用时由框架自动重置。 */
@ReusableV2
@ComponentV2
export struct GalleryRow {
  @Require @Param item: GalleryRowItem;

  build() {
    Row({ space: 12 }) {
      // 缩略图容器：共享元素绑定处（转场同步容器圆角；子 Image 只负责填满）。
      Column() {
        if (this.item.thumb.length > 0) {
          Image(this.item.thumb)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }
      }
      .width(84)
      .height(84)
      .borderRadius(THUMB_RADIUS)
      .clip(true)
      .backgroundColor($r('app.color.bg_primary'))
      .geometryTransition(galleryGeometryId(this.item.gid))
      // 官方要求：配合 transition 保证离场组件不被立即析构（与 animateTo 一起）。
      .transition(TransitionEffect.OPACITY)
      Column({ space: 4 }) {
        Text(this.item.title.length > 0 ? this.item.title : `gid ${this.item.gid}`)
          .fontSize(14)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Row({ space: 6 }) {
          Text(catLabel(this.item.category))
            .fontSize(11)
            .fontColor(Color.White)
            .backgroundColor(catColor(this.item.category))
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          if (rowLine1(this.item).length > 0) {
            Text(rowLine1(this.item))
              .fontSize(12)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (rowLine2(this.item).length > 0) {
          Text(rowLine2(this.item))
            .fontSize(12)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(10)
    // 卡片形态：统一圆角/底色（令牌见 `ui/Materials.ets`），不再用行分隔线；
    // 页面留白与行间距由调用方 `ListItem` 的 padding 承担（卡片自带 margin 会与 width('100%') 溢出）。
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
  }
}
