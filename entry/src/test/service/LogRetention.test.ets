import { describe, it, expect } from '@ohos/hypium';
import {
  APP_LOG_DEPTH,
  APP_LOG_LIMIT_BYTES,
  FAULT_KEEP_COUNT,
  FaultFile,
  KEEP_DAYS,
  SWEEP_INTERVAL_MS,
  faultsToDelete,
  shouldRotate,
  shouldSweep
} from '../../main/ets/service/LogRetention';

const DAY: number = 24 * 3600 * 1000;

export default function logRetentionTest() {
  describe('LogRetention', () => {
    it('constants_match_design', 0, () => {
      expect(APP_LOG_LIMIT_BYTES).assertEqual(1048576);
      expect(APP_LOG_DEPTH).assertEqual(3);
      expect(FAULT_KEEP_COUNT).assertEqual(5);
      expect(KEEP_DAYS).assertEqual(7);
      expect(SWEEP_INTERVAL_MS).assertEqual(3 * DAY);
    });

    it('should_sweep_on_first_launch_and_every_interval', 0, () => {
      const now: number = 1000 * DAY;
      expect(shouldSweep(0, now)).assertTrue();
      expect(shouldSweep(now - 2 * DAY, now)).assertFalse();
      expect(shouldSweep(now - 3 * DAY, now)).assertTrue();
      expect(shouldSweep(now + DAY, now)).assertTrue();
    });

    it('deletes_faults_older_than_keep_days', 0, () => {
      const now: number = 100 * DAY;
      const files: FaultFile[] = [];
      for (let i = 0; i < 3; i++) {
        files.push({ name: `old${i}.txt`, bytes: 10, mtimeMs: now - 8 * DAY });
      }
      for (let i = 0; i < 5; i++) {
        files.push({ name: `new${i}.txt`, bytes: 10, mtimeMs: now - i * 1000 });
      }
      const deleted: string[] = faultsToDelete(files, now);
      expect(deleted.length).assertEqual(3);
      expect(deleted.indexOf('old0.txt') >= 0).assertTrue();
      expect(deleted.indexOf('new0.txt')).assertEqual(-1);
    });

    it('keeps_only_newest_when_count_exceeds_limit', 0, () => {
      const now: number = 100 * DAY;
      const files: FaultFile[] = [];
      for (let i = 0; i < 7; i++) {
        files.push({ name: `f${i}.txt`, bytes: 10, mtimeMs: now - (7 - i) * 1000 });
      }
      const deleted: string[] = faultsToDelete(files, now);
      expect(deleted.length).assertEqual(2);
      expect(deleted.indexOf('f0.txt') >= 0).assertTrue();
      expect(deleted.indexOf('f1.txt') >= 0).assertTrue();
      expect(deleted.indexOf('f6.txt')).assertEqual(-1);
    });

    it('rotates_only_when_limit_reached', 0, () => {
      expect(shouldRotate(APP_LOG_LIMIT_BYTES - 1, APP_LOG_LIMIT_BYTES)).assertFalse();
      expect(shouldRotate(APP_LOG_LIMIT_BYTES, APP_LOG_LIMIT_BYTES)).assertTrue();
      expect(shouldRotate(0, APP_LOG_LIMIT_BYTES)).assertFalse();
    });
  });
}
