import { TopListRange } from '../network/EhUrl';

/** 排行时间档项（`tl` 值见 `EhUrl.toplist`；站点语义不翻译）。 */
export interface RankRangeItem {
  label: string;
  range: TopListRange;
}

/** 排行时间档（顺序即标题栏胶囊顺序）。 */
export const RANK_RANGES: RankRangeItem[] = [
  { label: '昨日', range: 'yesterday' },
  { label: '月榜', range: 'month' },
  { label: '年榜', range: 'year' },
  { label: '总榜', range: 'all' }
];

/**
 * 排行档位（跨 `AppShell` 标题栏与 `TopListPage` 共享）。
 *
 * 连接方式（在 UI 组件里调用）：`AppStorageV2.connect(RankState, () => new RankState())`。
 * 标题栏胶囊只写 `range`；`version` 每次换档 +1，列表页用 `@Monitor` 订阅后重载
 * （不用 `range` 自身做监听：同档重复点击不应重载）。
 */
@ObservedV2
export class RankState {
  @Trace range: TopListRange = 'yesterday';
  @Trace version: number = 0;

  /** 切档：同档为空操作（返回是否真的换了档，供调用方决定要不要滚动/提示）。 */
  select(range: TopListRange): boolean {
    if (this.range === range) {
      return false;
    }
    this.range = range;
    this.version += 1;
    return true;
  }
}
