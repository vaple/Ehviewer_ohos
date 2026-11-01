/**
 * 搜索框联想候选（一行）。
 * `ns` / `tag` 是站点英文原串——选中后写回输入框的是 `ns:"tag$"`，**实际搜索始终用原串**；
 * `name` 是中文名，只用于显示与匹配；`intro` 是释义，空串表示没有（UI 据此决定是否留第二行）。
 */
export interface TagCandidate {
  ns: string;
  tag: string;
  name: string;
  intro: string;
}
