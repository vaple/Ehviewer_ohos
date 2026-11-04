/**
 * 筛选面板的目录（标签 / 位值 / 短名）。
 *
 * 页面与抽屉各自需要一半：页面用 `SCOPES` + `scopeShort` 拼收起态摘要，
 * 抽屉用 `CATS` / `STARS` / `SCOPES` 渲染 chip。放一处共享，避免两份目录漂移
 * （漏掉一个分类位 → 站点收到错误的 `f_cats`，是看不见的数据错误）。
 *
 * 全部是**站点英文原文**（分类与范围不翻译，见 AGENTS §7）。
 */

/** 分类 chip 项（位值对照源 `EhConfig`；点亮 = 选中该分类 → 换算排除集发 `f_cats`）。 */
export interface CatItem {
  label: string;
  bit: number;
}

export const CATS: CatItem[] = [
  { label: 'DOUJINSHI', bit: 0x2 },
  { label: 'MANGA', bit: 0x4 },
  { label: 'ARTIST CG', bit: 0x8 },
  { label: 'GAME CG', bit: 0x10 },
  { label: 'IMAGE SET', bit: 0x20 },
  { label: 'COSPLAY', bit: 0x40 },
  { label: 'ASIAN PORN', bit: 0x80 },
  { label: 'NON-H', bit: 0x100 },
  { label: 'WESTERN', bit: 0x200 },
  { label: 'MISC', bit: 0x1 }
];

/** 搜索范围 chip 项（`f_sname/f_stags/f_sdesc/f_storr`；选中 = 只搜该范围）。 */
export interface ScopeItem {
  label: string;
  key: string;
}

export const SCOPES: ScopeItem[] = [
  { label: 'Gallery Name', key: 'title' },
  { label: 'Gallery Tags', key: 'tags' },
  { label: 'Gallery Description', key: 'desc' },
  { label: 'Torrents', key: 'torrents' }
];

/** 最低星级档（源 spinner `position + 2`）。 */
export const STARS: number[] = [2, 3, 4, 5];

/** 范围短名（收起态摘要用；`f_s*` 语义不变，仅展示从简）。 */
export function scopeShort(key: string): string {
  if (key === 'title') {
    return '名称';
  }
  if (key === 'tags') {
    return '标签';
  }
  if (key === 'desc') {
    return '描述';
  }
  return '种子';
}
