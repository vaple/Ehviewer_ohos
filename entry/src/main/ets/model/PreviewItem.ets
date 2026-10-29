/** 详情预览项（`#gdt` 锚点；`page` 内部 0 起；`x/y/w/h` 为格子自带裁剪矩形，图片像素）。 */
export interface PreviewItem {
  page: number;
  pToken: string;
  imageUrl: string;
  x: number;
  y: number;
  w: number;
  h: number;
}
