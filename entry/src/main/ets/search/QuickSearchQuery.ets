import { QuickSearch } from '../model/QuickSearch';
import { SearchParam } from '../model/SearchParam';
import {
  decodeAdvance, selectedFromExcluded, ALL_CATS, searchKindOf, exactTagQuery
} from './SearchQuery';
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
 * 快搜记录的 `keyword` → `f_search` 条件主体。
 *
 * `mode` 是老记录唯一能说明「这条查询当年是什么模式」的线索：1 = 上传者，恢复时**必须**
 * 补 `uploader:"…"` qualifier——裸名字会被当普通关键词，搜出一堆无关画廊。
 * 2 = 标签，归一到精确语法（修复前存的裸 `parody:blue archive` 再运行也仍是精确标签搜索）。
 * 0 原样返回：keyword 就是完整的查询串（含用户手写的 qualifier）。
 */
function restoredQuery(keyword: string, mode: number): string {
  if (mode === 1) {
    return `uploader:"${keyword.trim()}"`;
  }
  if (mode === 2) {
    return exactTagQuery(keyword);
  }
  return keyword;
}

/**
 * 快搜记录 → 搜索路由参数（含落库四条件；老记录 `category/advanceSearch` 为 0 即默认态）。
 * `kind` 仍按 `mode` 还原：保存侧用它在列表里区分来源；URL 只由 `queryText` 决定，不再有特殊拼接。
 * 纯函数，行为即断言。
 */
export function quickSearchToParam(item: QuickSearch): SearchParam {
  const decoded = decodeAdvance(item.advanceSearch);
  const kind = searchKindOf(item.mode);
  return {
    query: restoredQuery(item.keyword, item.mode),
    title: item.name,
    kind: kind,
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
