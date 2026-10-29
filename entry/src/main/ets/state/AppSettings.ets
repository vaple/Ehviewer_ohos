import { EhSite } from '../network/EhUrl';
import { ReadingDirection } from '../reader/ReaderMode';
import { ConfigurationConstant } from '@kit.AbilityKit';

/**
 * 应用设置：站点 / 阅读方向 / 显示模式 / 预加载窗口。
 *
 * 连接方式（在 UI 组件里调用，**不要**在本类或 `EntryAbility` 里提前连接）：
 * ```
 * PersistenceV2.globalConnect({ type: AppSettings, key: 'AppSettings9', defaultCreator: () => new AppSettings() })
 * ```
 * 落盘只依赖 `@Trace` 成员，且**必须逐属性赋值**（`settings.site = x`）——整体替换对象不会触发持久化。
 *
 * 注意：字段结构一旦落盘就不能再改（增删 `@Trace` 字段会让旧 blob 反序列化失败、
 * 连接建不起来、之后所有写入都丢）。再加字段时必须换新 key（当前 `AppSettings9`），
 * 代价是用户已有设置重置一次。
 */
@ObservedV2
export class AppSettings {
  /** 站点：默认 E 站；浏览/阅读请选 EX（已登录账号访问 E 站首页拿到的是会员版页面，没有画廊列表）。 */
  @Trace site: EhSite = EhSite.E;
  /** 阅读方向。 */
  @Trace readerDirection: ReadingDirection = ReadingDirection.LTR;
  /** 显示模式：0=跟随系统 / 1=浅色 / 2=深色（见 `displayModeToColorMode`）。 */
  @Trace displayMode: number = 0;
  /** 缩略图尺寸（源 `Settings.getThumbResolution`：0 原图 / 1 `_250` / 2 `_300`）。 */
  @Trace thumbSize: number = 0;
  /** 阅读器前向预加载页数（0–10；默认 3）。 */
  @Trace prefetchAhead: number = 3;
  /** 阅读器后向预加载页数（0–10；默认 10）。 */
  @Trace prefetchBehind: number = 10;
}

/**
 * 显示模式 → 系统颜色模式（`ApplicationContext.setColorMode` 用）。
 * 0 跟随系统（NOT_SET，冷启动重应用同样值）/ 1 浅色 / 2 深色；非法值回跟随系统。
 */
export function displayModeToColorMode(mode: number): ConfigurationConstant.ColorMode {
  if (mode === 1) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }
  if (mode === 2) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
}
