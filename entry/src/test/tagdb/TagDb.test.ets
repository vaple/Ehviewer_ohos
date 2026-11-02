import { describe, it, expect, afterEach } from '@ohos/hypium';
import { pickNewerSnapshot, TagDb, TagDbPick, tagDbRev } from '../../main/ets/tagdb/TagDb';
import { parseTagDb } from '../../main/ets/tagdb/TagDbFormat';
import { TagSettings } from '../../main/ets/state/TagSettings';

/**
 * 只走 `TagDb.install(...)` 与纯函数这条纯内存路径：本地单测没有 UI 上下文，
 * `resourceManager` / `fs` / `context` 在这里都不可用（加载器本身靠真机日志验证）。
 */
const FIXTURE: string =
  '#tagdb\t1\n' +
  '#source\tcafe\t2026-11-02T00:00:00Z\n' +
  '#rows\n' +
  'female\t女性\n' +
  '#tags\n' +
  'female\tsample tags\t示例标签\n' +
  '#intro\n' +
  'female\tsample tags\t示例释义文本。\n';

/** 较新的一份（用于"沙箱更新"场景）。 */
const FIXTURE_NEWER: string =
  '#tagdb\t1\n' +
  '#source\tnewer\t2026-11-02T00:00:00Z\n' +
  '#rows\n' +
  'female\t女性\n' +
  '#tags\n' +
  'female\tsample tags\t新译名\n' +
  '#intro\n';

/** 较旧的一份（用于"App 升级带来新内置快照"场景）。 */
const FIXTURE_OLDER: string =
  '#tagdb\t1\n' +
  '#source\tolder\t2026-10-01T00:00:00Z\n' +
  '#rows\n' +
  'female\t女性\n' +
  '#tags\n' +
  'female\tsample tags\t旧译名\n' +
  '#intro\n';

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

      expect(TagDb.translateTag('female', 'sample tags')).assertEqual('示例标签');
      // 未命中必须是原文，不是空串/占位符（否则界面和没装翻译时不一样）。
      expect(TagDb.translateTag('female', 'not in db')).assertEqual('not in db');
      expect(TagDb.translateNs('female')).assertEqual('女性');
      expect(TagDb.translateNs('male')).assertEqual('male');
      expect(TagDb.intro('female', 'sample tags')).assertEqual('示例释义文本。');
      expect(TagDb.intro('female', 'not in db')).assertEqual('');
      expect(TagDb.search('示例', 10).length).assertEqual(1);
      expect(TagDb.search('', 10).length).assertEqual(0);
    });

    it('disabled_setting_releases_data_and_bumps_rev', 0, () => {
      const settings: TagSettings = new TagSettings();
      TagDb.bindSettings(settings);
      TagDb.install(parseTagDb(FIXTURE), 'bundled');
      expect(TagDb.isReady()).assertTrue();

      // 只改开关就该生效：访问器（setter）驱动 dropData（释放 ≈8 MB）+ rev++，页面不需要自己调 reload。
      const before: number = tagDbRev.rev;
      settings.enabled = false;
      expect(TagDb.isReady()).assertFalse();
      expect(tagDbRev.rev).assertEqual(before + 1);
      expect(TagDb.status() === undefined).assertTrue();
      expect(TagDb.translateTag('female', 'sample tags')).assertEqual('sample tags');
      expect(TagDb.translateNs('female')).assertEqual('female');
      expect(TagDb.intro('female', 'sample tags')).assertEqual('');
      expect(TagDb.search('示例', 10).length).assertEqual(0);

      // 重新打开：测试里没有 context（不能读文件），所以仍由 install 喂数据——只验证门禁解除。
      settings.enabled = true;
      TagDb.install(parseTagDb(FIXTURE), 'bundled');
      expect(TagDb.isReady()).assertTrue();
      expect(TagDb.translateTag('female', 'sample tags')).assertEqual('示例标签');
      expect(TagDb.search('示例', 10).length).assertEqual(1);
    });

    it('disabled_before_install_keeps_no_data', 0, () => {
      const settings: TagSettings = new TagSettings();
      settings.enabled = false;
      TagDb.bindSettings(settings);
      TagDb.install(parseTagDb(FIXTURE), 'bundled');

      expect(TagDb.isReady()).assertFalse();
      expect(TagDb.status() === undefined).assertTrue();
    });

    // spec §7：两份都有效时取 `builtAt` 较新的。选片是纯函数，之后走与加载器相同的 install 路径。

    it('newer_sandbox_snapshot_wins', 0, () => {
      const pick: TagDbPick | undefined =
        pickNewerSnapshot(parseTagDb(FIXTURE_NEWER), parseTagDb(FIXTURE_OLDER));
      expect(pick === undefined).assertFalse();
      if (pick === undefined) {
        return;
      }
      expect(pick.source).assertEqual('updated');
      TagDb.install(pick.data, pick.source);

      const status = TagDb.status();
      expect(status === undefined).assertFalse();
      if (status !== undefined) {
        // 状态行展示的就是这份：日期/来源必须来自胜出的沙箱快照，不能混进内置的。
        expect(status.builtAt).assertEqual('2026-11-02T00:00:00Z');
        expect(status.sha).assertEqual('newer');
      }
    });

    it('newer_bundled_snapshot_wins_over_stale_sandbox', 0, () => {
      // App 升级场景：内置更新，但沙箱里那份仍能解析、只是更旧——不能被它压住。
      const pick: TagDbPick | undefined =
        pickNewerSnapshot(parseTagDb(FIXTURE_OLDER), parseTagDb(FIXTURE_NEWER));
      expect(pick === undefined).assertFalse();
      if (pick === undefined) {
        return;
      }
      expect(pick.source).assertEqual('bundled');
      TagDb.install(pick.data, pick.source);

      expect(TagDb.translateTag('female', 'sample tags')).assertEqual('新译名');
      const status = TagDb.status();
      expect(status === undefined).assertFalse();
      if (status !== undefined) {
        expect(status.source).assertEqual('bundled');
        expect(status.builtAt).assertEqual('2026-11-02T00:00:00Z');
      }
    });
  });
}
