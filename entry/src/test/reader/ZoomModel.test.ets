import { describe, it, expect } from '@ohos/hypium';
import {
  applyPinch, nextDoubleTapScale, panTranslate, clampOffset,
  isImmersiveDelaySafe, IMMERSIVE_DELAY_MS, DOUBLE_TAP_WINDOW_MS,
  ZOOM_MIN, ZOOM_MAX, DOUBLE_TAP_SCALE
} from '../../main/ets/reader/ZoomModel';

export default function zoomModelTest() {
  describe('ZoomModel', () => {
    it('apply_pinch_clamps_to_range', 0, () => {
      expect(applyPinch(1, 2, ZOOM_MIN, ZOOM_MAX)).assertEqual(2);
      expect(applyPinch(3, 2, ZOOM_MIN, ZOOM_MAX)).assertEqual(4);
      expect(applyPinch(1, 0.1, ZOOM_MIN, ZOOM_MAX)).assertEqual(1);
      expect(applyPinch(2, 0.5, ZOOM_MIN, ZOOM_MAX)).assertEqual(1);
    });

    it('double_tap_toggles_between_min_and_max', 0, () => {
      expect(nextDoubleTapScale(1, ZOOM_MAX)).assertEqual(4);
      expect(nextDoubleTapScale(2, ZOOM_MAX)).assertEqual(1);
      expect(nextDoubleTapScale(1.0001, ZOOM_MAX)).assertEqual(1);
    });

    it('clamp_offset_follows_scale', 0, () => {
      // content = 绘制尺寸；limit = (content*scale - view)/2
      expect(clampOffset(999, 100, 100, 2)).assertEqual(50);
      expect(clampOffset(-999, 100, 100, 2)).assertEqual(-50);
      expect(clampOffset(10, 100, 100, 1)).assertEqual(0);
      expect(clampOffset(10, 100, 100, 1.5)).assertEqual(10);
    });

    // `ImageFit.Contain` 会把图片按短边缩小：留黑的轴上 content < view，即使放大到 4 倍也拖不动，
    // 按容器夹取（content=view）则会允许拖出黑边 —— 真机实测到过整块黑边。
    it('clamp_offset_uses_drawn_content_not_container', 0, () => {
      // 竖图放在宽容器里：宽 50 / 容器 100 → 4 倍时绘制 200，仍可动 ±50
      expect(clampOffset(999, 100, 50, 4)).assertEqual(50);
      // 同尺寸横向：绘制 400 − 容器 100 → 可动 ±150
      expect(clampOffset(999, 100, 100, 4)).assertEqual(150);
      // 绘制尺寸还没拿到（content=0）→ 退回容器，scale=1 时不许动
      expect(clampOffset(999, 100, 0, 1)).assertEqual(0);
    });

    // 真机实测：scale=4 时手指走 705.88vp、`PanGesture.offsetX` 只报 176.22vp（比值恒为 1/scale）。
    // 不换算就慢 4 倍 —— 表现为「放大后拖不动、到不了边」。
    it('pan_offset_is_local_and_needs_scale_back', 0, () => {
      expect(panTranslate(25, 4)).assertEqual(100);
      expect(panTranslate(10, 1)).assertEqual(10);
      expect(panTranslate(-12.5, 2)).assertEqual(-25);
    });

    // 单击延迟必须**严格大于** SDK 的双击窗口（`TapGesture` 两次抬起之间 300ms）。
    // 落在窗口以内时，稍慢的双击会先让单击定时器跑完 → 操作栏真切一次 → 「双击顺带闪一下」。
    it('immersive_delay_outlives_double_tap_window', 0, () => {
      expect(DOUBLE_TAP_WINDOW_MS).assertEqual(300);
      expect(isImmersiveDelaySafe(IMMERSIVE_DELAY_MS)).assertTrue();
      expect(isImmersiveDelaySafe(300)).assertFalse();
      // 旧值 280ms 就落在窗口内 —— 保留这条，防止有人改回去。
      expect(isImmersiveDelaySafe(280)).assertFalse();
    });

    // 纵向看图层：`Scroll` 只有在 `minZoomScale/maxZoomScale` 非 1 时才自动启用捏合
    // （SDK `scroll.d.ts` 明文）。这两个值的约束写死，防止有人把范围改成 1 而把捏合关掉。
    it('zoom_viewer_range_enables_official_pinch', 0, () => {
      expect(ZOOM_MIN).assertEqual(1);
      expect(ZOOM_MAX).assertEqual(4);
      // 范围必须真的放开（任一为 1 等于关闭官方缩放手势）
      expect(ZOOM_MAX > ZOOM_MIN).assertTrue();
    });

    // 双击倍率与捏合上限是**两个**概念：双击给一个舒服的默认值（2 倍），
    // 想要更大就让用户自己捏（上限仍是 ZOOM_MAX=4）。
    // 曾经两者共用 ZOOM_MAX，导致双击一下就到顶、没法再捏，观感也太猛。
    it('double_tap_scale_is_gentler_than_pinch_max', 0, () => {
      expect(DOUBLE_TAP_SCALE).assertEqual(2);
      expect(DOUBLE_TAP_SCALE < ZOOM_MAX).assertTrue();
      // 双击给 DOUBLE_TAP_SCALE，不是 ZOOM_MAX
      expect(nextDoubleTapScale(ZOOM_MIN, DOUBLE_TAP_SCALE)).assertEqual(DOUBLE_TAP_SCALE);
      // 只要已经放大（> 1），双击一律复位退出 —— 与「捏到 3 倍再双击」一致
      expect(nextDoubleTapScale(DOUBLE_TAP_SCALE, DOUBLE_TAP_SCALE)).assertEqual(ZOOM_MIN);
      expect(nextDoubleTapScale(3, DOUBLE_TAP_SCALE)).assertEqual(ZOOM_MIN);
      expect(nextDoubleTapScale(1.0001, DOUBLE_TAP_SCALE)).assertEqual(ZOOM_MIN);
    });
  });
}
