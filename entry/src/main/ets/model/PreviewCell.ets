/**
 * 预览格（远端缩略图 URL + 站点自带裁剪矩形；渲染走 `ui/PreviewCropCell`）。
 *
 * 页码语义与站点一致：**0 起**（站点 URL 里是 1 起，解析器已减 1）。
 * 详情页预览网格与跳页半模态共用同一结构，所以放在 model 层。
 */
@ObservedV2
export class PreviewCell {
  page: number = 0;
  @Trace url: string = '';
  @Trace x: number = 0;
  @Trace y: number = 0;
  @Trace w: number = 0;
  @Trace h: number = 0;
}
