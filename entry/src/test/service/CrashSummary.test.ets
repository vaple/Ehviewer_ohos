import { describe, it, expect } from '@ohos/hypium';
import { CrashFields, crashReport, faultFileName, isProbablyText, parseCrashParams, pathsOf } from '../../main/ets/service/CrashSummary';

export default function crashSummaryTest() {
  describe('CrashSummary', () => {
    it('parses_missing_fields_to_defaults', 0, () => {
      const params: Record<string, Object> = { 'crash_type': 'JsError' };
      const f: CrashFields = parseCrashParams(params);
      expect(f.crashType).assertEqual('JsError');
      expect(f.hilogLines.length).assertEqual(0);
      expect(f.externalLogs.length).assertEqual(0);
      expect(f.exception).assertEqual('');
    });

    it('parses_arrays_and_numbers', 0, () => {
      const params: Record<string, Object> = {
        'time': 1000,
        'crash_type': 'NativeCrash',
        'pid': 42,
        'process_life_time': 7,
        'bundle_version': '1.0.0',
        'external_log': ['/data/x/cppcrash.txt'],
        'hilog': ['line-1', 'line-2']
      };
      const f: CrashFields = parseCrashParams(params);
      expect(f.timeMs).assertEqual(1000);
      expect(f.pid).assertEqual(42);
      expect(f.processLifeMs).assertEqual(7000);
      expect(f.externalLogs.length).assertEqual(1);
      expect(f.hilogLines.length).assertEqual(2);
    });

    it('paths_of_handles_plain_and_json_array', 0, () => {
      expect(pathsOf('').length).assertEqual(0);
      expect(pathsOf('/data/x/a.log').length).assertEqual(1);
      const parsed: string[] = pathsOf('["/data/x/a.log","/data/x/b.log"]');
      expect(parsed.length).assertEqual(2);
      expect(parsed[1]).assertEqual('/data/x/b.log');
    });

    it('detects_text_vs_binary_by_nul_byte', 0, () => {
      expect(isProbablyText(new Uint8Array([0x47, 0x65, 0x6e, 0x65]))).assertTrue();
      expect(isProbablyText(new Uint8Array([0x7f, 0x45, 0x4c, 0x46, 0x00, 0x01]))).assertFalse();
    });

    it('fault file names are unique per index', 0, () => {
      const ts: number = new Date(2026, 9, 27, 1, 55, 12).getTime();
      expect(faultFileName(ts, 'NativeCrash', 0, '.txt')).assertEqual('20261027-015512_NativeCrash_0.txt');
      expect(faultFileName(ts, 'NativeCrash', 1, '.dmp')).assertEqual('20261027-015512_NativeCrash_1.dmp');
    });

    it('report_has_meta_line_and_hilog_lines', 0, () => {
      const f: CrashFields = {
        timeMs: new Date(2026, 9, 27, 9, 5, 7, 42).getTime(),
        crashType: 'JsError',
        bundleVersion: '1.0.0',
        pid: 42,
        processLifeMs: 7000,
        exception: 'TypeError: x is undefined',
        hilogLines: ['h1', 'h2', 'h3'],
        externalLogs: [],
        pageSwitchLog: ''
      };
      const report: string = crashReport(f);
      const lines: string[] = report.split('\n');
      expect(lines[0].indexOf('== crash 2026-10-27 09:05:07.042') === 0).assertTrue();
      expect(lines[1].indexOf('crash_type=JsError') === 0).assertTrue();
      expect(report.indexOf('TypeError: x is undefined') > 0).assertTrue();
      expect(report.indexOf('h3') > 0).assertTrue();
    });
  });
}
