/**
 * 骨架屏占位块（官方 FAQ「应用加载页面时有短暂的白屏」的流光写法）：
 * 底色块 + `linearGradient` 高光层 + `translate` 循环（1500ms / 无限）。
 *
 * 约束边界：这只用于「内容未到」的占位动画；**页面/标题栏/浮层的装饰性遮罩与转场**
 * 仍必须走官方材质/转场 API，不自绘（见 `Materials.ets`）。
 */
@ComponentV2
export struct SkeletonBlock {
  /** 参数名避开 `width`/`height`（与组件基类的通用属性方法同名会编译失败）。 */
  @Param w: Length = '100%';
  @Param h: Length = 16;
  @Param corner: number = 6;
  @Local shift: string = '-100%';

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(this.corner)
        .backgroundColor($r('app.color.skeleton_bg'))
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(this.corner)
        .translate({ x: this.shift })
        .onAppear(() => {
          this.shift = '100%';
        })
        .animation({ duration: 1500, iterations: -1, curve: Curve.Linear })
        .linearGradient({
          angle: 90,
          colors: [
            [$r('app.color.skeleton_highlight_transparent'), 0],
            [$r('app.color.skeleton_highlight'), 0.5],
            [$r('app.color.skeleton_highlight_transparent'), 1]
          ]
        })
    }
    .width(this.w)
    .height(this.h)
    .borderRadius(this.corner)
    .clip(true)
  }
}
