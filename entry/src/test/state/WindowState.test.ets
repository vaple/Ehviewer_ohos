import { describe, it, expect } from '@ohos/hypium';
import { WindowState } from '../../main/ets/state/WindowState';

/** 窗口安全区（纯内存状态）。连接走 `AppStorageV2`。 */
export default function windowStateTest() {
  describe('WindowState', () => {
    it('defaults_to_zero_safe_area', 0, () => {
      const state: WindowState = new WindowState();
      expect(state.safeTop).assertEqual(0);
      expect(state.safeBottom).assertEqual(0);
    });

    it('safe_area_is_assignable_and_readable', 0, () => {
      const state: WindowState = new WindowState();
      state.safeTop = 136;
      state.safeBottom = 48;
      expect(state.safeTop).assertEqual(136);
      expect(state.safeBottom).assertEqual(48);
    });
  });
}
