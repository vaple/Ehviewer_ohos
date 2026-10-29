import { describe, it, expect } from '@ohos/hypium';
import { hdsMaterial } from '@kit.UIDesignKit';
import { materialLevelFor } from '../../main/ets/ui/Materials';

export default function materialsTest() {
  describe('Materials', () => {
    // 设备支持 IMMERSIVE 时交系统自适应（FAQ 1095 场景三推荐写法）。
    it('materialLevelFor_supported_uses_adaptive', 0, () => {
      expect(materialLevelFor(true)).assertEqual(hdsMaterial.MaterialLevel.ADAPTIVE);
    });

    // 不支持 IMMERSIVE 时降 SMOOTH，避免低算力设备卡顿发热。
    it('materialLevelFor_unsupported_falls_back_smooth', 0, () => {
      expect(materialLevelFor(false)).assertEqual(hdsMaterial.MaterialLevel.SMOOTH);
    });

    // 两档必须不同：否则上面两条会同时通过而分支形同虚设。
    it('materialLevelFor_branches_differ', 0, () => {
      expect(materialLevelFor(true) === materialLevelFor(false)).assertFalse();
    });
  });
}
