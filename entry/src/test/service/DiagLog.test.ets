import { describe, it, expect } from '@ohos/hypium';
import { DiagStats, statsSummary } from '../../main/ets/service/DiagLog';

const HOUR: number = 3600 * 1000;
const DAY: number = 24 * HOUR;

function statsOf(totalBytes: number, lastCrashMs: number): DiagStats {
  return {
    totalBytes: totalBytes,
    appFiles: 1,
    crashFiles: 0,
    faultCount: 0,
    lastCrashMs: lastCrashMs,
    sinceMs: 0
  };
}

export default function diagLogTest() {
  describe('DiagLog', () => {
    it('summary_without_logs', 0, () => {
      const empty: DiagStats = {
        totalBytes: 0,
        appFiles: 0,
        crashFiles: 0,
        faultCount: 0,
        lastCrashMs: 0,
        sinceMs: 0
      };
      expect(statsSummary(empty, 100 * DAY)).assertEqual('还没有日志');
    });

    it('summary_without_crash_shows_size_only', 0, () => {
      const text: string = statsSummary(statsOf(812 * 1024, 0), 100 * DAY);
      expect(text.indexOf('812.0 KB') === 0).assertTrue();
      expect(text.indexOf('无崩溃记录') > 0).assertTrue();
    });

    it('summary_reports_days_since_last_crash', 0, () => {
      const now: number = 100 * DAY;
      const text: string = statsSummary(statsOf(1024, now - 3 * DAY), now);
      expect(text.indexOf('3 天前') > 0).assertTrue();
    });

    it('summary_reports_hours_and_just_now', 0, () => {
      const now: number = 100 * DAY;
      expect(statsSummary(statsOf(1024, now - HOUR), now).indexOf('1 小时前') > 0).assertTrue();
      expect(statsSummary(statsOf(1024, now - 30 * 1000), now).indexOf('刚刚') > 0).assertTrue();
    });
  });
}
