/** FILTER 表实体（「搜索排除」预设）。`mode` 决定拼接查询时的前缀：0 = title、1 = uploader、2 = tag。 */
export interface Filter {
  id: number;
  mode: number;
  text: string;
  enable: boolean;
}
