import { describe, it, expect } from '@ohos/hypium';
import { ExportMeta, exportName, metaJson } from '../../main/ets/service/LogExport';

export default function logExportTest() {
  describe('LogExport', () => {
    it('export name is timestamped', 0, () => {
      const ts: number = new Date(2026, 9, 27, 22, 4, 5).getTime();
      expect(exportName(ts)).assertEqual('ehviewer-logs-20261027-220405.zip');
    });

    it('meta json round trips', 0, () => {
      const meta: ExportMeta = {
        version: '1.0.0',
        apiVersion: 26,
        model: 'Test Device',
        site: 'E-Hentai',
        lang: 'zh',
        loggedIn: true,
        exportedAtMs: 1000
      };
      const parsed: ExportMeta = JSON.parse(metaJson(meta)) as ExportMeta;
      expect(parsed.version).assertEqual('1.0.0');
      expect(parsed.apiVersion).assertEqual(26);
      expect(parsed.loggedIn).assertTrue();
    });
  });
}
