import { describe, it, expect, afterEach } from '@ohos/hypium';
import { TagDb, tagDbRev } from '../../main/ets/tagdb/TagDb';
import { parseTagDb } from '../../main/ets/tagdb/TagDbFormat';
import { TagSettings } from '../../main/ets/state/TagSettings';

/**
 * 只走 `TagDb.install(...)` 这条纯内存路径：本地单测没有 UI 上下文，
 * `resourceManager` / `fs` / `context` 在这里都不可用（加载器本身靠真机日志验证）。
 */
const FIXTURE: string =
  '#tagdb\t1\n' +
  '#source\tcafe\t2026-11-02T00:00:00Z\n' +
  '#rows\n' +
  'female\t女性\n' +
  '#tags\n' +
  'female\tbig breasts\t巨乳\n' +
  '#intro\n' +
  'female\tbig breasts\t一般的大乳房。\n';

export default function tagDbTest() {
  describe('TagDb', () => {
    // 模块级单例：不清就会把数据/订阅漏给后面的用例（也掩盖「关闭后是否真释放」）。
    afterEach(() => {
      TagDb.__resetForTest();
    });

    it('install_makes_it_ready_and_reports_status', 0, () => {
      const before: number = tagDbRev.rev;
      TagDb.install(parseTagDb(FIXTURE), 'bundled');

      expect(TagDb.isReady()).assertTrue();
      // install 是唯一的重绘信号出口：chip 靠它从原文切到中文。
      expect(tagDbRev.rev).assertEqual(before + 1);

      const status = TagDb.status();
      expect(status === undefined).assertFalse();
      if (status !== undefined) {
        expect(status.source).assertEqual('bundled');
        expect(status.sha).assertEqual('cafe');
        expect(status.builtAt).assertEqual('2026-11-02T00:00:00Z');
        expect(status.count).assertEqual(1);
      }
    });

    it('install_records_updated_source', 0, () => {
      // `source` 是设置页「内置快照 / 已更新」的唯一依据，不能被硬编码成 bundled。
      TagDb.install(parseTagDb(FIXTURE), 'updated');

      const status = TagDb.status();
      expect(status === undefined).assertFalse();
      if (status !== undefined) {
        expect(status.source).assertEqual('updated');
      }
    });

    it('translates_hits_and_falls_back_to_raw', 0, () => {
      TagDb.install(parseTagDb(FIXTURE), 'updated');

      expect(TagDb.translateTag('female', 'big breasts')).assertEqual('巨乳');
      // 未命中必须是原文，不是空串/占位符（否则界面和没装翻译时不一样）。
      expect(TagDb.translateTag('female', 'not in db')).assertEqual('not in db');
      expect(TagDb.translateNs('female')).assertEqual('女性');
      expect(TagDb.translateNs('male')).assertEqual('male');
      expect(TagDb.intro('female', 'big breasts')).assertEqual('一般的大乳房。');
      expect(TagDb.intro('female', 'not in db')).assertEqual('');
      expect(TagDb.search('巨', 10).length).assertEqual(1);
      expect(TagDb.search('', 10).length).assertEqual(0);
    });

    it('disabled_setting_releases_data_and_bumps_rev', 0, () => {
      const settings: TagSettings = new TagSettings();
      TagDb.bindSettings(settings);
      TagDb.install(parseTagDb(FIXTURE), 'bundled');
      expect(TagDb.isReady()).assertTrue();

      // 只改开关就该生效：@Monitor 驱动 dropData（释放 ≈8 MB）+ rev++，页面不需要自己调 reload。
      const before: number = tagDbRev.rev;
      settings.enabled = false;
      expect(TagDb.isReady()).assertFalse();
      expect(tagDbRev.rev).assertEqual(before + 1);
      expect(TagDb.status() === undefined).assertTrue();
      expect(TagDb.translateTag('female', 'big breasts')).assertEqual('big breasts');
      expect(TagDb.translateNs('female')).assertEqual('female');
      expect(TagDb.intro('female', 'big breasts')).assertEqual('');
      expect(TagDb.search('巨', 10).length).assertEqual(0);

      // 重新打开：测试里没有 context（不能读文件），所以仍由 install 喂数据——只验证门禁解除。
      settings.enabled = true;
      TagDb.install(parseTagDb(FIXTURE), 'bundled');
      expect(TagDb.isReady()).assertTrue();
      expect(TagDb.translateTag('female', 'big breasts')).assertEqual('巨乳');
      expect(TagDb.search('巨', 10).length).assertEqual(1);
    });

    it('disabled_before_install_keeps_no_data', 0, () => {
      const settings: TagSettings = new TagSettings();
      settings.enabled = false;
      TagDb.bindSettings(settings);
      TagDb.install(parseTagDb(FIXTURE), 'bundled');

      expect(TagDb.isReady()).assertFalse();
      expect(TagDb.status() === undefined).assertTrue();
    });
  });
}
