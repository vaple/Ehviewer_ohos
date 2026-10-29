import { LengthMetrics } from '@kit.ArkUI';
import { BlurStrategy, ScrollEffectType, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { HDS_MATERIAL } from './Materials';

/** HDS 标题栏高度（MINI；各页内容顶部避让与渐变终点共用）。 */
export const TITLE_BAR_H: number = 56;
/** 标题栏底部功能区（排行档位胶囊）高度（vp）。 */
export const RANK_CHIPS_H: number = 52;

/**
 * 所有 push 页共用的官方标题栏样式：
 * 官方「渐变模糊」（`GRADIENT_BLUR`，空间渐变、边界柔和）+ 透明底 + 主题文字色。
 * 用一处常量保证「设置/收藏/历史/屏蔽/评论/搜索」与首页、详情观感一致，不再出现「毛坯房」。
 */
export function navTitleBarStyle(): TitleBarStyleOptions {
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_H)
    },
    blurStrategy: BlurStrategy.ADAPTIVE,
    originalStyle: {
      backgroundStyle: { backgroundColor: Color.Transparent },
      contentStyle: { titleStyle: { mainTitleColor: $r('app.color.text_primary') } }
    },
    scrollEffectStyle: {
      backgroundStyle: { backgroundColor: Color.Transparent }
    },
    // 与首页/我的同一档位：标题栏按钮区吃 HDS 沉浸光感材质（系统自适应/降级在 Materials 单点控制）。
    systemMaterialEffect: HDS_MATERIAL
  };
}
