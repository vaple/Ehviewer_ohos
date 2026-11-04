/**
 * 结果列表的加载指示器（下拉刷新 + 程序化搜索共用）。
 *
 * `Refresh` 会把 `builder` 里的自定义内容挤压到刷新区域顶部：浅下拉时连 `LoadingProgress` 的高度
 * 都被压掉一半，圈总是画在容器顶边（沉浸布局下就是页面 y=0，落在状态栏 / 挖孔下面）。
 * 所以内置区域只放零高占位，圈由页面级覆盖层画在内容起始线，位置与下拉距离无关。
 *
 * `busy` 是程序化请求（回车 / 筛选「应用」/ 点 chip）的信号：那时没有下拉位移，
 * 而列表底部那条提示通常滚在屏幕外——不在这里给一个常亮圈，用户会觉得"点了没反应"。
 */
@ComponentV2
export struct RefreshSpinner {
  /** 下拉位移（vp）：大于 0 才显示。 */
  @Param pullOffset: number = 0;
  /** 正在刷新：常亮。 */
  @Param isRefreshing: boolean = false;
  /** 有请求在飞（程序化搜索）：常亮。 */
  @Param busy: boolean = false;
  /** 内容起始线的 y（安全区 + 标题栏 + 页面自带功能区）。 */
  @Param top: number = 0;

  build() {
    if (this.busy || this.pullOffset > 0 || this.isRefreshing) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color($r('app.color.text_secondary'))
        // 下拉越深越实，进入刷新/请求后常亮，松手归零后一起消失。
        .opacity(this.busy || this.isRefreshing ? 1 : Math.min(1, this.pullOffset / 32))
        .margin({ top: this.top })
    }
  }
}
