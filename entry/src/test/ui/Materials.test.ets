import { describe, it, expect } from '@ohos/hypium';
import { hdsMaterial } from '@kit.UIDesignKit';
import { COMMENT_BAR_MATERIAL, commentBackdrop, CommentBackdrop, materialLevelFor } from '../../main/ets/ui/Materials';

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

    // 支持沉浸材质：只挂材质，模糊必须关掉（两者同开会互相盖）。
    it('commentBackdrop_supported_uses_material_and_disables_blur', 0, () => {
      const b: CommentBackdrop = commentBackdrop(true, COMMENT_BAR_MATERIAL, BlurStyle.COMPONENT_ULTRA_THICK);
      expect(b.material === COMMENT_BAR_MATERIAL).assertTrue();
      expect(b.blur).assertEqual(BlurStyle.NONE);
    });

    // 不支持沉浸材质：必须退回官方模糊，否则删掉 blur 后容器完全透明（真机上评论会叠字）。
    it('commentBackdrop_unsupported_falls_back_to_blur', 0, () => {
      const b: CommentBackdrop = commentBackdrop(false, COMMENT_BAR_MATERIAL, BlurStyle.COMPONENT_ULTRA_THICK);
      expect(b.material === undefined).assertTrue();
      expect(b.blur).assertEqual(BlurStyle.COMPONENT_ULTRA_THICK);
    });
  });
}
