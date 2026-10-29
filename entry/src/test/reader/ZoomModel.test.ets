import { describe, it, expect } from '@ohos/hypium';
import { applyPinch, nextDoubleTapScale, clampOffset, ZOOM_MIN, ZOOM_MAX } from '../../main/ets/reader/ZoomModel';

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
      expect(clampOffset(999, 100, 2)).assertEqual(50);
      expect(clampOffset(-999, 100, 2)).assertEqual(-50);
      expect(clampOffset(10, 100, 1)).assertEqual(0);
      expect(clampOffset(10, 100, 1.5)).assertEqual(10);
    });
  });
}
