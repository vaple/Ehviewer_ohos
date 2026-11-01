import { PersistenceV2 } from '@kit.ArkUI';

/**
 * 标签翻译总开关（独立持久化类）。
 *
 * 为什么不并进 `AppSettings`：按 `state/AGENTS.md` #24，给已落盘的类加 `@Trace` 字段必须换持久化 key
 * （`AppSettings9` → `10`），代价是用户所有设置（站点/缩略图/显示模式）重置一次；
 * 为一个布尔值不值。独立类 + 独立 key 可以随时增字段，只需换自己的 key。
 *
 * 连接方式（在 UI 组件里用 `@Local`/普通字段初始化器，**不要**在 `EntryAbility` 里提前连接）：
 * ```
 * PersistenceV2.globalConnect({ type: TagSettings, key: 'TagSettings2', defaultCreator: () => new TagSettings() })
 * ```
 * 落盘只依赖 `@Trace` 成员，且必须**逐属性赋值**（`settings.enabled = false`）。
 *
 * **为什么是 `TagSettings2`**：`TagSettings1` 落盘过 `"enabled": true`，而本类现在把字段改名为
 * `enabledValue`（`enabled` 成了访问器）——字段名变了就是结构变化，PersistenceV2 反序列化旧 blob 可能失败、
 * 连接建不起来，`globalConnect(...)!` 会给出 `undefined`，之后读 `settings.enabled` 直接崩。
 * key 换代是唯一安全的做法；本功能尚未发布，迁移成本为零。**不要复用 `TagSettings1`**，
 * 也不要再往已落盘的 key 上改字段名（改结构 → 换 key，见 `state/AGENTS.md` #24）。
 */

/** 开关变化监听（由 `TagDb` 安装；页面只改 `enabled`，不需要自己调 `reload`）。 */
export type TagEnabledListener = (enabled: boolean) => void;

/** 全局只有一个监听者：`TagDb` 是单例。 */
let enabledListener: TagEnabledListener | undefined = undefined;

/** 安装 / 解除（`undefined`）开关监听。 */
export function watchTagEnabled(listener: TagEnabledListener | undefined): void {
  enabledListener = listener;
}

@ObservedV2
export class TagSettings {
  /**
   * 真实存储字段：`@Trace` 落盘 + 供 UI 建立依赖。
   * 名字带 `Value` 是因为对外暴露的 `enabled` 是原型上的访问器——访问器不会被当成第二个字段序列化。
   */
  @Trace private enabledValue: boolean = true;

  /** 关闭 = 不加载快照（不占 ~8 MB）、所有标签显示原文、搜索不给中文候选。 */
  get enabled(): boolean {
    return this.enabledValue;
  }

  /**
   * 写：先落状态（持久化 + UI 重算），再把变化推给 `TagDb`（关 → 立刻释放数据并 `rev++`）。
   *
   * 为什么不用 `@Monitor('enabled')`：本地单测的运行时里 `@Monitor` 完全不回调（实测：连
   * 测试内自定义的 `@ObservedV2` 类也不触发，同步/异步都一样），那样「关闭真的释放内存」这条契约
   * 就没有任何自动化保障；访问器在单测与真机上行为一致。同值赋值不重复触发，避免多余的 I/O。
   */
  set enabled(value: boolean) {
    if (value === this.enabledValue) {
      return;
    }
    this.enabledValue = value;
    if (enabledListener !== undefined) {
      enabledListener(value);
    }
  }
}
