import { describe, it, expect } from '@ohos/hypium';
import { ReadingProgressStore } from '../../main/ets/state/ReadingProgressStore';

const CAP: number = ReadingProgressStore.MAX_ENTRIES;

/** 阅读进度逻辑（gid → 页码，0 起）+ LRU 上限。持久化落盘不在这里测。 */
export default function readingProgressStoreTest() {
  describe('ReadingProgressStore', () => {
    it('save_then_load_roundtrip_uses_zero_based_page', 0, () => {
      const store: ReadingProgressStore = new ReadingProgressStore();
      store.save(123456, 0);
      expect(store.load(123456)).assertEqual(0);

      store.save(123456, 7);
      expect(store.load(123456)).assertEqual(7);
    });

    it('load_unknown_returns_minus_one', 0, () => {
      const store: ReadingProgressStore = new ReadingProgressStore();
      expect(store.load(1)).assertEqual(-1);

      store.save(123456, 7);
      expect(store.load(123456)).assertEqual(7);
    });

    it('lru_evicts_oldest_beyond_cap', 0, () => {
      const store: ReadingProgressStore = new ReadingProgressStore();
      for (let gid = 1; gid <= CAP + 1; gid++) {
        store.save(gid, gid - 1);
      }

      expect(store.size()).assertEqual(CAP);
      expect(store.load(1)).assertEqual(-1);
      expect(store.load(CAP + 1)).assertEqual(CAP);
    });

    it('load_touches_lru_order_so_recent_survives_eviction', 0, () => {
      const store: ReadingProgressStore = new ReadingProgressStore();
      for (let gid = 1; gid <= CAP; gid++) {
        store.save(gid, 0);
      }
      expect(store.load(1)).assertEqual(0);

      store.save(CAP + 1, 0);

      expect(store.load(2)).assertEqual(-1);
      expect(store.load(1)).assertEqual(0);
    });

    it('cap_holds_under_repeated_inserts', 0, () => {
      const store: ReadingProgressStore = new ReadingProgressStore();
      for (let gid = 1; gid <= CAP * 3; gid++) {
        store.save(gid, 0);
      }

      expect(store.size()).assertEqual(CAP);
      expect(store.load(CAP * 2)).assertEqual(-1);
      expect(store.load(CAP * 2 + 1)).assertEqual(0);
      expect(store.load(CAP * 3)).assertEqual(0);
    });

    it('big_gid_keys_stay_distinct', 0, () => {
      const store: ReadingProgressStore = new ReadingProgressStore();
      store.save(999999998, 41);
      store.save(999999999, 42);

      expect(store.size()).assertEqual(2);
      expect(store.load(999999998)).assertEqual(41);
      expect(store.load(999999999)).assertEqual(42);
    });
  });
}
