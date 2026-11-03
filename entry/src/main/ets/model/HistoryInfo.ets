import { GalleryInfo } from './GalleryInfo';

/** HISTORY 表实体：画廊信息 + 阅读时间。 */
export interface HistoryInfo extends GalleryInfo {
  time: number;
}
