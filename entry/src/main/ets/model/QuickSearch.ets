/** QUICK_SEARCH 表实体（真实列；`id` 为 0 表示未持久化）。 */
export interface QuickSearch {
  id: number;
  name: string;
  mode: number;
  category: number;
  keyword: string;
  /** 语言 chip（`language:xxx` 站点原文；空 = 不过滤）。 */
  language: string;
  advanceSearch: number;
  minRating: number;
  pageFrom: number;
  pageTo: number;
  time: number;
}
