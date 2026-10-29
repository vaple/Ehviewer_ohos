/** 画廊列表项的基础信息（对应上游 Android 版 EhViewer GalleryInfo 的持久化字段）。 */
export interface GalleryInfo {
  gid: number;
  token: string;
  title: string;
  titleJpn: string;
  thumb: string;
  category: number;
  posted: string;
  uploader: string;
  rating: number;
  simpleLanguage: string;
  /** 总页数（列表 HTML `N pages`；缺失为 0，调用方跳过展示）。 */
  pages: number;
}
