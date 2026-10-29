/** 搜索页路由参数（照 `DetailParam` 现例）。四条件可选：缺字段回退默认（老快搜记录无条件，只带 keyword）。 */
export type SearchKind = 'keyword' | 'uploader' | 'tag';

export interface SearchParam {
  query: string;
  title: string;
  kind: SearchKind;
  /** 点亮的分类位（正选语义；缺省 = 10 位全亮）。 */
  selectedBits?: number[];
  /** 搜索范围（`SCOPES` 的 key 子集；缺省 = 不限范围）。 */
  scopes?: string[];
  /** 语言过滤（缺省 false）。 */
  langFilter?: boolean;
  /** 语言 chip（`language:xxx` 站点原文；缺省空 = 不过滤）。 */
  language?: string;
  /** 最低星级（缺省 -1 = 关）。 */
  minRating?: number;
}
