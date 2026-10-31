import { PersistenceV2 } from '@kit.ArkUI';
import { isNewer } from '../network/ReleaseClient';

/**
 * 更新检查结果（应用级持久化）。
 *
 * 连接方式（在 UI 组件里用 `@Local`/普通字段初始化器，**不要**在 `EntryAbility` 里提前连接）：
 * ```
 * PersistenceV2.globalConnect({ type: UpdateState, key: 'UpdateState1', defaultCreator: () => new UpdateState() })
 * ```
 * 落盘只依赖 `@Trace` 成员，且**必须逐属性赋值**（整对象替换不会触发持久化）。
 *
 * 注意：字段结构一旦落盘就不能再改（增删 `@Trace` 字段会让旧 blob 反序列化失败）；再加字段必须换新 key。
 */
@ObservedV2
export class UpdateState {
  /** 最近一次**成功**检查的时间（0 = 从未查过）。 */
  @Trace lastCheckAtMs: number = 0;
  /** 最近一次检查是否成功（决定关于页显示「上次检查失败」而不是「已是最新」）。 */
  @Trace lastCheckOk: boolean = false;
  /** 远端 tag 原文，如 `v1.1.0`（展示用）。 */
  @Trace latestTag: string = '';
  /** 去前缀后的版本号（比较用）。 */
  @Trace latestVersion: string = '';
  /** release 说明原文（不做 Markdown 处理）。 */
  @Trace notes: string = '';
  /** 安装包资产原名（保存面板的默认文件名）。 */
  @Trace hapName: string = '';
  /** GitCode 下载地址（两源同版本时才有；下载优先用它）。 */
  @Trace gitcodeUrl: string = '';
  /** GitHub 下载地址（两源同版本时才有，作为同版本的备选）。 */
  @Trace githubUrl: string = '';
  /** 「稍后」截止时间（0 = 没稍后过）。 */
  @Trace snoozeUntilMs: number = 0;
}

/** 全局连接（应用级持久化）。 */
export function updateState(): UpdateState {
  return PersistenceV2.globalConnect({
    type: UpdateState,
    key: 'UpdateState1',
    defaultCreator: () => new UpdateState()
  })!;
}

/** 远端是否比本地新（红点与提示的唯一判据；本机版本变大后自动变 `false`）。 */
export function hasUpdate(state: UpdateState, current: string): boolean {
  return isNewer(state.latestVersion, current);
}

/** 下载地址：优先 GitCode，回落 GitHub（两者都空 → `''`）。 */
export function downloadUrlOf(state: UpdateState): string {
  return state.gitcodeUrl.length > 0 ? state.gitcodeUrl : state.githubUrl;
}

/** 「稍后」的时长：24 小时（用户 2026-10-30 决定：安静一天，红点保留）。 */
export const SNOOZE_MS: number = 24 * 60 * 60 * 1000;

/**
 * 关于页顶部的一行结论。
 * 顺序不能变：没查过 → 上次失败 → 比版本，否则会把「没查过」说成「已是最新」（等于编数据）。
 */
export function updateSummary(state: UpdateState, current: string): string {
  if (state.lastCheckAtMs === 0) {
    return '尚未检查';
  }
  if (!state.lastCheckOk) {
    return '上次检查失败';
  }
  if (hasUpdate(state, current)) {
    return `有新版本 ${state.latestVersion}`;
  }
  return '当前已是最新';
}
