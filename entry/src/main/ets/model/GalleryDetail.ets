import { GalleryComment } from './GalleryComment';
import { PreviewItem } from './PreviewItem';
import { TagGroup } from './TagGroup';

/** 详情页模型。 */
export interface GalleryDetail {
  gid: number;
  token: string;
  title: string;
  titleJpn: string;
  category: number;
  uploader: string;
  posted: string;
  rating: number;
  ratingCount: number;
  pages: number;
  thumb: string;
  /** 标签分组（`#taglist` 按解析序；空组不收录）。 */
  tagGroups: TagGroup[];
  /** 预览页 pToken（按页序，`previewTokens[page-1]`）；仅详情页给出的前若干页。 */
  previewTokens: string[];
  /** 预览项（`#gdt` 锚点：缩略图 + 页；首块随详情 HTML 自带）。 */
  previews: PreviewItem[];
  /** 评分接口凭证（详情页 `var apiuid/apikey`；游客为 `-1`/空串）。 */
  apiUid: number;
  apiKey: string;
  /** 评论列表（页面 `#cdiv`；无评论为空数组）。 */
  comments: GalleryComment[];
  /** 是否已收藏（详情页 `#gdf` 文本 `Add to Favorites` = 未收藏；源 `GalleryDetailParser` 同判据）。 */
  isFavorited: boolean;
  /** 已收藏时的收藏夹名（站点原文，如 `Favorites 0`）；未收藏为空串。 */
  favoriteName: string;
}
