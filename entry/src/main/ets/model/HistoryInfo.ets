import { GalleryInfo } from './GalleryInfo';

/** HISTORY 表实体：画廊信息 + 阅读模式与时间。 */
export interface HistoryInfo extends GalleryInfo {
  mode: number;
  time: number;
}
