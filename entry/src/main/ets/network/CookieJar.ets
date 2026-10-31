/**
 * Cookie 仓库的最小接口（`EhClient` 只用到这三件事）。
 *
 * 抽接口的目的：让 `EhClient` 不再直接依赖 `CookieStore`（后者绑 `@kit.ArkData`），
 * 本地单测即可注入 fake，无需设备就能断言「缓存命中不发请求」。
 */
export interface CookieJar {
  /** 当前全部 Cookie（拼请求用）。 */
  all(): Record<string, string>;
  set(name: string, value: string): void;
  flush(): Promise<void>;
}
