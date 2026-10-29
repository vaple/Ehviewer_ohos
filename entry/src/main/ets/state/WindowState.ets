/**
 * 窗口状态（**纯内存**，不落盘）：系统安全区（vp）。
 *
 * 连接方式（在 UI 组件里调用）：`AppStorageV2.connect(WindowState, () => new WindowState())`
 * —— 用 `AppStorageV2` 而不是 `PersistenceV2`：安全区不需要跨重启保存。
 *
 * `safeTop` / `safeBottom` 由 `AppShell` 在启动与窗口尺寸变化时用
 * `window.getWindowAvoidArea()` 写入；页面顶部避让一律读这里，**不写死机型高度**。
 */
@ObservedV2
export class WindowState {
  /** 顶部状态栏高度（vp）。 */
  @Trace safeTop: number = 0;
  /** 底部手势条 / 导航条高度（vp）。 */
  @Trace safeBottom: number = 0;
}
