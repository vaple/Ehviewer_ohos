import { QuickSearch } from '../model/QuickSearch';
import { SearchParam } from '../model/SearchParam';
import { decodeAdvance, selectedFromExcluded, ALL_CATS } from './SearchQuery';
import { catLabel } from '../ui/CategoryStyle';

/** 是否已存过同名关键词（大小写不敏感；去重存用）。 */
export function hasSavedKeyword(items: QuickSearch[], keyword: string): boolean {
  const word: string = keyword.trim().toLowerCase();
  for (let i = 0; i < items.length; i++) {
    if (items[i].keyword.trim().toLowerCase() === word) {
      return true;
    }
  }
  return false;
}

/**
 * 快搜记录 → 搜索路由参数（含落库四条件；老记录 `category/advanceSearch` 为 0 即默认态）。
 *
 * `keyword` 存的就是**最终** `f_search` 主体，这里原样发出，不做任何语法改写。
 * `kind` 恒为 `keyword`：`tag` 那条「精确入口不套屏蔽规则」只对**直接进入**成立，
 * 存成快搜再跑就是一次普通搜索——同一条查询不该因为从哪个入口存而结果不同。
 * 纯函数，行为即断言。
 */
export function quickSearchToParam(item: QuickSearch): SearchParam {
  const decoded = decodeAdvance(item.advanceSearch);
  return {
    query: item.keyword.trim(),
    kind: 'keyword',
    selectedBits: selectedFromExcluded(item.category, ALL_CATS),
    scopes: decoded.scopes,
    langFilter: decoded.langFilter,
    language: item.language,
    minRating: item.minRating
  };
}

/**
 * 快搜条件摘要（列表副标题用；主标题是名，副标题讲清这条存了什么条件）。
 * 空条件回 `''`（调用方隐藏副标题）。纯函数，行为即断言。
 */
export function quickSearchSummary(item: QuickSearch): string {
  const parts: string[] = [];
  const excluded: string[] = [];
  for (let i = 0; i < ALL_CATS.length; i++) {
    if ((item.category & ALL_CATS[i]) !== 0) {
      excluded.push(catLabel(ALL_CATS[i]));
    }
  }
  if (excluded.length > 0) {
    parts.push(excluded.length <= 3 ? `排除 ${excluded.join('/')}` : `排除${excluded.length}类`);
  }
  const decoded = decodeAdvance(item.advanceSearch);
  if (decoded.scopes.length > 0) {
    parts.push(decoded.scopes.join('/'));
  }
  if (item.language.length > 0) {
    parts.push(item.language);
  }
  if (decoded.langFilter) {
    parts.push('语言筛选');
  }
  if (item.minRating === 2 || item.minRating === 3 ||
    item.minRating === 4 || item.minRating === 5) {
    parts.push(`★${item.minRating}+`);
  }
  return parts.join(' · ');
}
