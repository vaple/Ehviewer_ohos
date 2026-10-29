import { describe, it, expect } from '@ohos/hypium';
import { AppSettings, displayModeToColorMode } from '../../main/ets/state/AppSettings';
import { EhSite } from '../../main/ets/network/EhUrl';
import { ReadingDirection } from '../../main/ets/reader/ReaderMode';

/** 设置类逻辑（站点 / 阅读方向 / 显示模式）。持久化落盘不在这里测。 */
export default function appSettingsTest() {
  describe('AppSettings', () => {
    it('defaults_are_e_ltr', 0, () => {
      const settings: AppSettings = new AppSettings();
      expect(settings.site).assertEqual(EhSite.E);
      expect(settings.readerDirection).assertEqual(ReadingDirection.LTR);
    });

    it('per_property_assignment_reads_back', 0, () => {
      const settings: AppSettings = new AppSettings();
      settings.site = EhSite.EX;
      settings.readerDirection = ReadingDirection.VERTICAL;

      expect(settings.site).assertEqual(EhSite.EX);
      expect(settings.readerDirection).assertEqual(ReadingDirection.VERTICAL);
    });

    it('displayMode_defaults_to_follow_system', 0, () => {
      expect(new AppSettings().displayMode).assertEqual(0);
    });

    it('displayMode_maps_to_color_mode', 0, () => {
      expect(displayModeToColorMode(0)).assertEqual(-1);
      expect(displayModeToColorMode(1)).assertEqual(1);
      expect(displayModeToColorMode(2)).assertEqual(0);
    });
  });
}
