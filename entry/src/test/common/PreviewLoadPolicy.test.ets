import { describe, it, expect } from '@ohos/hypium';
import {
  MAX_LOAD_SCREENS_PER_SECOND, screensPerSecond, shouldLoadAtSpeed
} from '../../main/ets/common/PreviewLoadPolicy';

export default function previewLoadPolicyTest() {
  describe('PreviewLoadPolicy', () => {
    it('screens_per_second_normalizes_by_viewport', 0, () => {
      // 1 秒走 1 个屏高 = 1 屏/秒，与屏高数值无关。
      expect(screensPerSecond(750, 750, 1000)).assertEqual(1);
      expect(screensPerSecond(1500, 750, 1000)).assertEqual(2);
      // 200ms 走 1/4 屏 = 1.25 屏/秒。
      expect(screensPerSecond(187.5, 750, 200)).assertEqual(1.25);
    });

    it('screens_per_second_is_direction_agnostic', 0, () => {
      expect(screensPerSecond(-1500, 750, 1000)).assertEqual(2);
    });

    it('invalid_viewport_or_window_returns_zero', 0, () => {
      expect(screensPerSecond(100, 0, 200)).assertEqual(0);
      expect(screensPerSecond(100, 750, 0)).assertEqual(0);
    });

    it('load_only_when_screen_dwell_is_long_enough', 0, () => {
      // 1.5 屏/秒 ⇔ 一屏停留 ~667ms；慢拖/慢惯性在内，快甩在外。
      expect(shouldLoadAtSpeed(0.3)).assertTrue();
      expect(shouldLoadAtSpeed(1.4)).assertTrue();
      expect(shouldLoadAtSpeed(MAX_LOAD_SCREENS_PER_SECOND)).assertTrue();
      expect(shouldLoadAtSpeed(1.6)).assertFalse();
      expect(shouldLoadAtSpeed(4)).assertFalse();
    });
  });
}
