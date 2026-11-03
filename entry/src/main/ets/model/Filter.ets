/** FILTER 表实体（「搜索排除」预设）。`text` 就是完整查询词（`title:…` / `-uploader:…` / `ns:"tag$"`）。 */
export interface Filter {
  id: number;
  text: string;
  enable: boolean;
}
