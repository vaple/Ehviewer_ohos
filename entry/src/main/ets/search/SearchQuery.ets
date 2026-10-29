/**
 * 搜索查询纯函数（源：`ListUrlBuilder.build` MODE_NORMAL / `EhConfig` 分类位）。
 * `fCatsMask` 取**排除位**的 OR（== 源 `(~selected) & ALL_CATEGORY`）；空数组 → 0（不发 `f_cats`）。
 */
import { SearchKind } from '../model/SearchParam';
import { Filter } from '../model/Filter';
export function fCatsMask(excludedCategories: number[]): number {
  let mask: number = 0;
  for (let i = 0; i < excludedCategories.length; i++) {
    mask |= excludedCategories[i];
  }
  return mask;
}

/**
 * 正选→排除换算（本站 `f_cats` 是排除语义，UI 层正选）。
 * `selected` 为当前点亮的分类位，`all` 为全部 10 位；返回 `all - selected`。
 * 空选（全不点亮）回 `[]` = 不发 `f_cats` = 全查，而不是查空（Review Focus #2）。
 */
export function excludedFromSelected(selected: number[], all: number[]): number[] {
  if (selected.length === 0) {
    return [];
  }
  const excluded: number[] = [];
  for (let i = 0; i < all.length; i++) {
    if (selected.indexOf(all[i]) < 0) {
      excluded.push(all[i]);
    }
  }
  return excluded;
}

/** 全部分类位（源 `EhConfig`；`SearchPage.CATS` 与此同序，改一处即改两处）。 */
export const ALL_CATS: number[] = [0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200, 0x1];

/**
 * 排除掩码→正选（快搜落库的逆操作；`QUICK_SEARCH.CATEGORY` 存排除掩码）。
 * 掩码 0 = 无排除 = 全选（含"空选全查"落库同样是 0，语义同 URL：不发 `f_cats`）。
 */
export function selectedFromExcluded(excludedMask: number, all: number[]): number[] {
  const selected: number[] = [];
  for (let i = 0; i < all.length; i++) {
    if ((excludedMask & all[i]) === 0) {
      selected.push(all[i]);
    }
  }
  return selected;
}

/** 站内搜索语言 chips（`language:xxx` 站点原文；对照源 `GalleryInfo.S_TAG_LANGS` + 可搜 `japanese`）。 */
export const SEARCH_LANGUAGES: string[] = [
  'japanese', 'english', 'chinese', 'spanish', 'korean', 'russian',
  'french', 'portuguese', 'thai', 'german', 'italian', 'vietnamese',
  'polish', 'hungarian', 'dutch'
];

/**
 * 快搜 `mode` → 搜索 `kind`（0 keyword / 1 uploader / 2 tag；非法回 keyword）。
 * 保存侧见 `SearchPage.saveQuick`（按 kind 存 0/1/2）。
 */
export function searchKindOf(mode: number): SearchKind {
  if (mode === 1) {
    return 'uploader';
  }
  if (mode === 2) {
    return 'tag';
  }
  return 'keyword';
}

/** 语言 chip → `f_search` 片段（单选精确串；空 = 不过滤）。 */
export function languageQueryOf(lang: string): string {
  if (lang.length === 0) {
    return '';
  }
  return `language:${lang}`;
}

/**
 * 屏蔽规则 → 搜索排除词（EHWiki `-` 排除语义；slave 用 master 名）：
 * 标题含空格加引号；上传者 `-uploader:名`（空格加引号）；标签（已是 `namespace:tag` 形）直接取；
 * 只取启用项；`ignored`（`mode:text` 键）跳单次忽略；上限 10 个（服务端上限）。
 */
/**
 * 排除规则 → 查询片段。规则 `text` 本身就是完整查询词：
 * `other:ai generated` / `uploader:名字` / `title:关键词`；含空格的值自动加引号。
 * 只取启用项；`ignored`（规则 text）跳单次忽略；上限 10 个（服务端上限）。
 */
export function exclusionQueryOf(rules: Filter[], ignored: string[]): string {
  const parts: string[] = [];
  for (let i = 0; i < rules.length && parts.length < 10; i++) {
    const rule: Filter = rules[i];
    if (!rule.enable || rule.text.length === 0) {
      continue;
    }
    if (ignored.indexOf(rule.text) >= 0) {
      continue;
    }
    parts.push(`-${qualifyTag(rule.text)}`);
  }
  return parts.join(' ');
}

/**
 * 含空格加引号（EHWiki 引号精确串）。
 * 已以 `"` 开头视为已包好 → 原样返回：规则文本可能本身来自 `exactTagQuery`，
 * 再包一层会得到 `parody:""blue archive$"`（源 `wrapTagKeyword` 同样先判首字符）。
 */
function quoteIfNeeded(word: string): string {
  if (word.startsWith('"')) {
    return word;
  }
  return word.indexOf(' ') >= 0 ? `"${word}"` : word;
}

/** `namespace:tag` 形只给 tag 部分加引号（无冒号视为裸词）。 */
export function qualifyTag(text: string): string {
  const at: number = text.indexOf(':');
  if (at < 0) {
    return quoteIfNeeded(text);
  }
  return `${text.substring(0, at + 1)}${quoteIfNeeded(text.substring(at + 1))}`;
}

/**
 * 标签查询串 → 站点正规精确语法 `namespace:"tag$"`。
 * EHWiki：引号把含空格的值并成单个词，`$` 是整词锚（`parody:blue` 会命中 `parody:blue archive` 这类 slave/长词，
 * 只有 `parody:"blue archive$"` 才是"就是这一个标签"）。源 `GalleryListScene.wrapTagKeyword` /
 * `SearchBar.rebuildKeyword` 同形，且对**所有**标签都加（不只带空格的）。
 * 幂等：已带首尾引号/尾部 `$` 先剥再包，所以快搜旧记录、手改文本重复路过都得到同一个串。
 * 无冒号视为裸关键词，原样返回（不替用户猜命名空间）。
 * 首字符的 `-`/`~` 前缀自然保留（`-parody:"blue archive$"`）。
 */
export function exactTagQuery(text: string): string {
  const src: string = text.trim();
  const at: number = src.indexOf(':');
  if (at < 0) {
    return src;
  }
  let value: string = src.substring(at + 1);
  if (value.startsWith('"')) {
    value = value.substring(1);
  }
  if (value.endsWith('"')) {
    value = value.substring(0, value.length - 1);
  }
  if (value.endsWith('$')) {
    value = value.substring(0, value.length - 1);
  }
  return `${src.substring(0, at + 1)}"${value}$"`;
}

/** `QUICK_SEARCH.ADVANCE_SEARCH` 位：搜索范围四位 + 语言过滤一位（本地定义，老记录 0 = 全默认）。 */
export const ADV_TITLE: number = 1;
export const ADV_TAGS: number = 2;
export const ADV_DESC: number = 4;
export const ADV_TORR: number = 8;
export const ADV_LANG: number = 16;

export interface DecodedAdvance {
  scopes: string[];
  langFilter: boolean;
}

/** 搜索范围 + 语言过滤 → 落库位掩码。 */
export function encodeAdvance(scopes: string[], langFilter: boolean): number {
  let mask: number = 0;
  if (scopes.indexOf('title') >= 0) {
    mask |= ADV_TITLE;
  }
  if (scopes.indexOf('tags') >= 0) {
    mask |= ADV_TAGS;
  }
  if (scopes.indexOf('desc') >= 0) {
    mask |= ADV_DESC;
  }
  if (scopes.indexOf('torrents') >= 0) {
    mask |= ADV_TORR;
  }
  if (langFilter) {
    mask |= ADV_LANG;
  }
  return mask;
}

/** 落库位掩码 → 搜索范围 + 语言过滤（未知位忽略）。 */
export function decodeAdvance(mask: number): DecodedAdvance {
  const scopes: string[] = [];
  if ((mask & ADV_TITLE) !== 0) {
    scopes.push('title');
  }
  if ((mask & ADV_TAGS) !== 0) {
    scopes.push('tags');
  }
  if ((mask & ADV_DESC) !== 0) {
    scopes.push('desc');
  }
  if ((mask & ADV_TORR) !== 0) {
    scopes.push('torrents');
  }
  return { scopes: scopes, langFilter: (mask & ADV_LANG) !== 0 };
}

/**
 * 高级搜索过滤（源 `ListUrlBuilder` + `AdvanceSearchTable`；仅 keyword 搜索用）。
 * `minRating` `-1` = 关，否则只认 2/3/4/5（源 spinner `position + 2`）。
 */
export interface SearchFilters {
  inTitle: boolean;
  inTags: boolean;
  inDesc: boolean;
  inTorrents: boolean;
  language: boolean;
  minRating: number;
  /** 只搜有种子（`f_sto=on`）。 */
  onlyTorrents: boolean;
  /** 忽略站点默认过滤（`f_sfl/f_sfu/f_sft`，语言/上传者/标签三开关一次性打开）。 */
  ignoreFilters: boolean;
  /** 页数区间（`-1` = 不限；`f_sp=on` 时生效）。 */
  pageFrom: number;
  pageTo: number;
}

/** 任一过滤激活（任一范围/语言/合法星级/有种子/忽略过滤/页数区间）。 */
export function filtersActive(f: SearchFilters): boolean {
  return f.inTitle || f.inTags || f.inDesc || f.inTorrents || f.language ||
    (f.minRating === 2 || f.minRating === 3 || f.minRating === 4 || f.minRating === 5) ||
    f.onlyTorrents || f.ignoreFilters || f.pageFrom > 0 || f.pageTo > 0;
}
