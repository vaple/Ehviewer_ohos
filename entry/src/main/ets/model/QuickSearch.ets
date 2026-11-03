/** QUICK_SEARCH 表实体（真实列；`id` 为 0 表示未持久化）。 */
export interface QuickSearch {
  id: number;
  category: number;
  /** 最终 `f_search` 主体（也是列表里显示的名字）。 */
  keyword: string;
  /** 语言 chip（`language:xxx` 站点原文；空 = 不过滤）。 */
  language: string;
  advanceSearch: number;
  minRating: number;
  time: number;
}
