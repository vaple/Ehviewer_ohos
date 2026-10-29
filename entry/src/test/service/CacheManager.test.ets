import { describe, it, expect } from '@ohos/hypium';
import { formatBytes } from '../../main/ets/common/Bytes';

export default function cacheManagerTest() {
  describe('CacheManager', () => {
    it('formatBytes_zero_and_small', 0, () => {
      expect(formatBytes(0)).assertEqual('0 B');
      expect(formatBytes(-1)).assertEqual('0 B');
      expect(formatBytes(512)).assertEqual('512 B');
    });

    it('formatBytes_kb_mb_gb', 0, () => {
      expect(formatBytes(1536)).assertEqual('1.5 KB');
      expect(formatBytes(12 * 1024 * 1024)).assertEqual('12.0 MB');
      expect(formatBytes(1024 * 1024 * 1024)).assertEqual('1.0 GB');
    });
  });
}
