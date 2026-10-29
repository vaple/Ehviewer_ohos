/**
 * 登录态（**纯内存**，不落盘）：以 `CookieStore` 是否含 `ipb_member_id` 为准。
 *
 * 连接方式（在 UI 组件里调用）：`AppStorageV2.connect(SessionState, () => new SessionState())`
 * —— 用 `AppStorageV2` 而不是 `PersistenceV2`：Cookie 本体已落盘，登录态每次按需重算；
 * `SettingsPage` 写 Cookie 后同步置位，供抽屉头/设置页即时展示（源 `MainActivity` 抽屉头同形）。
 */
@ObservedV2
export class SessionState {
  @Trace loggedIn: boolean = false;
  /** 系统配置版本（`EntryAbility.onConfigurationUpdate` 递增；深浅切换等触发订阅者重算）。 */
  @Trace configVersion: number = 0;
}
