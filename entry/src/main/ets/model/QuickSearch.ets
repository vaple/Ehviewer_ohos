/**
 * `SAVED` 列取值：`1` = 手动保存的快搜，`0` = 自动记录的搜索历史。
 *
 * 两者**共用一张表**：一条记录的形状完全一样（一次搜索的完整意图），
 * 只是生命周期不同（快搜永久、历史有上限）。分开建表会让 `quickSearchToParam`
 * 「记录 → 路由参数」的语义、摘要文案、行渲染各写两遍，改一处就要改两处。
 * 串用风险由 DAO 关住：页面只调 `querySaved()` / `queryHistory()`，不碰裸查询。
 */
export const SEARCH_SAVED: number = 1;
export const SEARCH_HISTORY: number = 0;

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
  /** `SEARCH_SAVED` = 快搜 / `SEARCH_HISTORY` = 历史。 */
  saved: number;
}
