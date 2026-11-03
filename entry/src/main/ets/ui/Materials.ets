import { hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { Logger } from '../common/Logger';

/**
 * 材质与版式令牌（档位集中在此）。
 *
 * 约定：
 * - 材质默认值只由 `module.json5` 的 `ohos.arkui.UIMaterial.state=enable` 决定
 *   （Chip / Select / SegmentButton / Toast / 半模态等默认吃系统材质），新增页面不要重复写组件级材质；
 * - HDS 组件走 `hdsMaterial.SystemMaterialParams`（`systemMaterialEffect`）；**普通组件**的
 *   `uiMaterial.ImmersiveMaterial`（`.systemMaterial()`）只在 NavDestination 标题栏和 End 位横向 Tabs
 *   底栏生效，内容区自定义容器（评论输入条/提示气泡）设了不渲染——那块只能用 `backgroundBlurStyle`；
 * - 任何材质都不要叠 `backgroundBlurStyle`：模糊层在材质之上，会把材质整块盖掉；
 * - HDS 没有对应组件的面（吸顶条等）用官方 `backgroundBlurStyle`，不自绘。
 */

/** 设备是否支持 HDS 沉浸材质（`getSystemMaterialTypes` 含 IMMERSIVE）。 */
function supportsImmersive(): boolean {
  return hdsMaterial.getSystemMaterialTypes().indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0;
}

/**
 * 材质等级：支持 IMMERSIVE 时交系统自适应（推荐写法），否则降 SMOOTH 防卡顿发热。
 * 纯函数（设备能力作入参），Local 单测覆盖。
 */
export function materialLevelFor(immersiveSupported: boolean): hdsMaterial.MaterialLevel {
  if (immersiveSupported) {
    return hdsMaterial.MaterialLevel.ADAPTIVE;
  }
  return hdsMaterial.MaterialLevel.SMOOTH;
}

/** HDS 组件材质参数（标题栏 / 悬浮底栏 / 任何吃 `systemMaterialEffect` 的 HDS 组件共用）。 */
export const HDS_MATERIAL: SystemMaterialParams = {
  materialType: hdsMaterial.MaterialType.ADAPTIVE,
  materialLevel: materialLevelFor(supportsImmersive())
};

// 档位只在此求值一次：打日志，避免"能力查询早于 UI 就绪"时静默降级成 SMOOTH 无从排查。
Logger.info('Materials', `hds material level=${HDS_MATERIAL.materialLevel} (IMMERSIVE support=${supportsImmersive()})`);

// 材质面只挂官方模糊，不叠 `sys.color.comp_background_*` 之类的底色令牌：
// 那些令牌不透明，叠上去会把模糊整块盖成实心。

/**
 * Sheet / 浮层材质由 `module.json5` 的全局开关（`ohos.arkui.UIMaterial.state=enable`）提供。
 *
 * **普通组件（Row/Column 等）的 `systemMaterial` 只在 `Navigation/NavDestination` 标题栏和
 * `barPosition=BarPosition.End` 的横向 Tabs 底栏生效**（官方《开启沉浸光感》明确列出），
 * 内容区里的自定义容器（评论输入条、提示气泡）设了也**不会渲染**——真机上表现为完全透明。
 * 内容区需要毛玻璃时只能用官方 `backgroundBlurStyle`；不要给这些容器写 `ImmersiveMaterial`。
 */

/** 页面横向留白（vp）。与 HDS `HdsListItemCard` 自带的 16vp 侧缩进对齐（同页不允许两套栅格）。 */
export const PAGE_PADDING: number = 16;
/** 卡片圆角（vp）。 */
export const CARD_RADIUS: number = 16;
/** 卡片间距（vp）。 */
export const CARD_GAP: number = 10;
/** 列表缩略图圆角（vp）。 */
export const THUMB_RADIUS: number = 12;
/** 可点区域最小边长（vp）。 */
export const TOUCH_MIN: number = 44;
/** 底部悬浮 tab 胶囊占位（vp）：`barBottomMargin 28` + 胶囊高 ~62 + 6 呼吸；列表末尾要留出这么多。 */
export const TAB_BAR_CLEARANCE: number = 96;
/** 详情页悬浮动作条：背板高度（vp，不含安全区）。 */
export const ACTION_BAR_H: number = 56;
/** 动作条主按钮高度（vp）。 */
export const ACTION_BAR_BTN_H: number = 44;
/** 动作条离屏幕底边的距离（vp）。注意：`HdsActionBar` 自己会避让底部安全区，**不要再叠 safeBottom**。 */
export const ACTION_BAR_MARGIN: number = 12;
/**
 * 跳页半模态高度（vp）。内容全是固定高度（输入 44 + 滑杆 + 提示 16 + 条带 140 + 间距），
 * 用固定挡位贴合内容；`SheetSize.FIT_CONTENT` 在真机上仍按默认 60% 渲染，会留一大片空白。
 */
export const JUMP_SHEET_H: number = 380;
/** 阅读选项半模态高度（vp）。内容只有「方向」段控件 + 两个开关行（约 200vp），
 * 默认挡位（LARGE）会拉成近全屏。同 `JUMP_SHEET_H`：`FIT_CONTENT` 真机不生效，只能给固定挡位。
 */
export const READER_SHEET_H: number = 260;
/** 评论输入胶囊高度（vp）。 */
export const COMMENT_BAR_H: number = 52;
/** 评论输入胶囊离屏幕底边的距离（vp，不含安全区）。 */
export const COMMENT_BAR_MARGIN: number = 12;

/**
 * 评论分数色：正分品牌色、负分危险色，`0` / 无分数沿用次级文字色。
 * `+5` / `-3` 的符号已经把含义说清，颜色只做扫读加速，不引入第三套语义色。
 */
export function commentScoreColor(score: number | undefined): ResourceColor {
  if (score === undefined || score === 0) {
    return $r('app.color.text_secondary');
  }
  return score > 0 ? $r('sys.color.brand') : $r('app.color.danger');
}
