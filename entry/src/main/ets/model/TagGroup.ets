/** 标签分组（一行 `#taglist tr`：`parody:` 等命名空间 + 行内 tag 文本）。 */
export interface TagGroup {
  namespace: string;
  tags: string[];
}
