/** 列表 → 详情快照（详情首帧即渲染；网络详情回来后覆盖并补齐 tags/评论/预览）。 */
export interface DetailPreview {
  title: string;
  /** 分类位值（`ParserUtils.CATEGORY_*`；未知为 `CATEGORY_UNKNOWN`）。 */
  category: number;
  uploader: string;
  rating: number;
  pages: number;
  /** 列表已落盘的本地缩略图 URI（有则首帧直接出图）。 */
  thumb: string;
  /** 远端封面地址（本地缺失时详情页补下载；与详情 `thumb` 同尺寸参数）。 */
  thumbUrl: string;
}

/** 列表 → 详情 传递参数。 */
export interface DetailParam {
  gid: number;
  token: string;
  /** 指定起始页（内部 0 起；缺省走进度恢复）。 */
  startPage?: number;
  /** 总页数（详情已知；阅读器首帧就能给出确定的分母，不再等网络）。 */
  pages?: number;
  /** 列表快照（可选；缺省则等网络详情，用于非列表入口）。 */
  preview?: DetailPreview;
}
