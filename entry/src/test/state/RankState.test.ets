import { describe, it, expect } from '@ohos/hypium';
import { RANK_RANGES, RankState } from '../../main/ets/state/RankState';

export default function rankStateTest() {
  describe('RankState', () => {
    it('defaults_to_yesterday', 0, () => {
      const state: RankState = new RankState();
      expect(state.range).assertEqual('yesterday');
      expect(state.version).assertEqual(0);
    });

    it('select_changes_range_and_bumps_version', 0, () => {
      const state: RankState = new RankState();
      expect(state.select('month')).assertTrue();
      expect(state.range).assertEqual('month');
      expect(state.version).assertEqual(1);
    });

    it('select_same_range_is_noop', 0, () => {
      const state: RankState = new RankState();
      expect(state.select('yesterday')).assertFalse();
      expect(state.version).assertEqual(0);
    });

    it('ranges_keep_site_semantics_order', 0, () => {
      expect(RANK_RANGES.length).assertEqual(4);
      expect(RANK_RANGES[0].range).assertEqual('yesterday');
      expect(RANK_RANGES[1].range).assertEqual('month');
      expect(RANK_RANGES[2].range).assertEqual('year');
      expect(RANK_RANGES[3].range).assertEqual('all');
    });
  });
}
