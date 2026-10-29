import { describe, it, expect } from '@ohos/hypium';
import { PersistenceV2 } from '@kit.ArkUI';
import { AppSettings } from '../../../main/ets/state/AppSettings';
import { ReadingProgressStore } from '../../../main/ets/state/ReadingProgressStore';
import { EhSite } from '../../../main/ets/network/EhUrl';
import { ReadingDirection } from '../../../main/ets/reader/ReaderMode';

/**
 * 持久化**读回**（只读断言）。
 *
 * 为什么只能只读：Instrument 测试上下文**写入不落盘**（没有 UI 实例，`haps/<test>/files/` 始终为空），
 * 所以写入路径靠「改设置 → 杀进程 → 重启仍是新值」人工核对。
 * App 没写过时这里读到的是默认值，因此这两条只防**解码 / 数据结构回归**
 * （例如枚举被解成越界值、`Map` 解不出来、LRU 上限失效）。
 */
export default function persistenceReadbackTest() {
  describe('PersistenceReadback', () => {
    it('app_settings_decodes_into_valid_ranges', 0, () => {
      const settings: AppSettings = PersistenceV2.globalConnect({
        type: AppSettings,
        key: 'AppSettings9',
        defaultCreator: () => new AppSettings()
      })!;

      expect(settings.site === EhSite.E || settings.site === EhSite.EX).assertTrue();
      const dir: number = settings.readerDirection;
      expect(dir >= ReadingDirection.LTR && dir <= ReadingDirection.VERTICAL).assertTrue();
    });

    it('reading_progress_decodes_within_cap', 0, () => {
      const progress: ReadingProgressStore = PersistenceV2.globalConnect({
        type: ReadingProgressStore,
        key: 'ReadingProgressStore',
        defaultCreator: () => new ReadingProgressStore()
      })!;

      expect(progress.size() <= ReadingProgressStore.MAX_ENTRIES).assertTrue();
      progress.pages.forEach((page: number, gid: string) => {
        expect(page >= 0).assertTrue();
        expect(gid.length > 0).assertTrue();
      });
    });
  });
}
