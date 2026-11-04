import { describe, it, expect } from '@ohos/hypium';
import { hdsMaterial } from '@kit.UIDesignKit';
import { materialLevelFor, sheetBackdropFor } from '../../main/ets/ui/Materials';

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

    // 支持沉浸材质：半模态走材质，底色必须透明（不透明底会盖住材质滤镜）。
    it('sheetBackdropFor_supported_uses_material', 0, () => {
      const backdrop = sheetBackdropFor(true, Color.White);
      expect(backdrop.material === undefined).assertFalse();
      expect(backdrop.backgroundColor).assertEqual(Color.Transparent);
    });

    // 不支持沉浸材质：材质无效果 → 必须留不透明底色，否则正文直接叠在页面上。
    it('sheetBackdropFor_unsupported_keeps_opaque', 0, () => {
      const backdrop = sheetBackdropFor(false, Color.White);
      expect(backdrop.material === undefined).assertTrue();
      expect(backdrop.backgroundColor).assertEqual(Color.White);
    });
  });
}
