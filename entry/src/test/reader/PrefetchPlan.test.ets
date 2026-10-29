import { describe, it, expect } from '@ohos/hypium';
import { clampPrefetch, neighbors, range, PREFETCH_MAX, PREFETCH_MIN } from '../../main/ets/reader/PrefetchPlan';

export default function prefetchPlanTest() {
  describe('PrefetchPlan', () => {
    it('clampPrefetch_bounds_and_rounding', 0, () => {
      expect(PREFETCH_MIN).assertEqual(0);
      expect(PREFETCH_MAX).assertEqual(10);
      expect(clampPrefetch(-3)).assertEqual(0);
      expect(clampPrefetch(0)).assertEqual(0);
      expect(clampPrefetch(3.4)).assertEqual(3);
      expect(clampPrefetch(3.6)).assertEqual(4);
      expect(clampPrefetch(10)).assertEqual(10);
      expect(clampPrefetch(99)).assertEqual(10);
      expect(clampPrefetch(Number.NaN)).assertEqual(0);
    });
    it('neighbors_around_middle', 0, () => {
      const r: number[] = neighbors(2, 5, 1, 1);
      expect(r.length).assertEqual(2);
      expect(r.includes(1)).assertTrue();
      expect(r.includes(3)).assertTrue();
      expect(r.includes(2)).assertFalse();
    });

    it('neighbors_clamped_at_edges', 0, () => {
      expect(neighbors(0, 5, 1, 1).length).assertEqual(1);
      expect(neighbors(0, 5, 1, 1)[0]).assertEqual(1);
      expect(neighbors(4, 5, 2, 2).length).assertEqual(2);
      expect(neighbors(4, 5, 2, 2)[0]).assertEqual(3);
    });

    it('neighbors_single_page_is_empty', 0, () => {
      expect(neighbors(0, 1, 2, 2).length).assertEqual(0);
    });

    it('range_includes_margin_and_clamps', 0, () => {
      const a: number[] = range(0, 1, 10, 1);
      expect(a.length).assertEqual(3);
      expect(a[0]).assertEqual(0);
      expect(a[2]).assertEqual(2);

      const b: number[] = range(8, 9, 10, 2);
      expect(b[0]).assertEqual(6);
      expect(b[b.length - 1]).assertEqual(9);
    });

    it('reader_default_window_ahead3_behind10', 0, () => {
      // 默认前 3 后 10（设置页可调 0–10）；先前后续。
      const r: number[] = neighbors(50, 300, 3, 10);
      expect(r.length).assertEqual(13);
      expect(r[0]).assertEqual(51);
      expect(r[2]).assertEqual(53);
      expect(r[3]).assertEqual(49);
      expect(r[12]).assertEqual(40);
    });

    it('reader_vertical_margin2', 0, () => {
      const r: number[] = range(10, 12, 100, 2);
      expect(r[0]).assertEqual(8);
      expect(r[r.length - 1]).assertEqual(14);
    });
  });
}
