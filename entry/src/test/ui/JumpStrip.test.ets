import { describe, it, expect } from '@ohos/hypium';
import {
  chunkOfPage, chunksInRange, prefetchChunks, centerSideOffset
} from '../../main/ets/common/JumpStrip';

export default function jumpStripTest() {
  describe('JumpStrip', () => {
    it('chunkOfPage_groups_by_20', 0, () => {
      expect(chunkOfPage(0)).assertEqual(0);
      expect(chunkOfPage(19)).assertEqual(0);
      expect(chunkOfPage(20)).assertEqual(1);
      expect(chunkOfPage(199)).assertEqual(9);
    });

    it('chunksInRange_covers_visible_window', 0, () => {
      expect(chunksInRange(0, 3, 200).join(',')).assertEqual('0');
      expect(chunksInRange(18, 22, 200).join(',')).assertEqual('0,1');
      expect(chunksInRange(3, 1, 200).join(',')).assertEqual('0');
    });

    it('chunksInRange_clamps_and_handles_empty', 0, () => {
      expect(chunksInRange(0, 0, 0).length).assertEqual(0);
      expect(chunksInRange(-4, 500, 45).join(',')).assertEqual('0,1,2');
      expect(chunksInRange(900, 950, 45).join(',')).assertEqual('2');
    });

    it('prefetchChunks_only_near_chunk_edges', 0, () => {
      expect(prefetchChunks(10, 12, 200, 5).length).assertEqual(0);
      expect(prefetchChunks(21, 23, 200, 5).join(',')).assertEqual('0');
      expect(prefetchChunks(17, 19, 200, 5).join(',')).assertEqual('1');
    });

    it('prefetchChunks_never_goes_out_of_bounds', 0, () => {
      expect(prefetchChunks(0, 2, 200, 5).length).assertEqual(0);
      expect(prefetchChunks(196, 199, 200, 5).length).assertEqual(0);
      expect(prefetchChunks(37, 39, 45, 5).join(',')).assertEqual('2');
    });

    it('prefetchChunks_honors_zero_edge_window', 0, () => {
      expect(prefetchChunks(10, 12, 200, 0).length).assertEqual(0);
      expect(prefetchChunks(20, 21, 200, 0).join(',')).assertEqual('0');
    });

    it('centerSideOffset_leaves_room_to_center_first_and_last', 0, () => {
      expect(centerSideOffset(360, 78)).assertEqual(141);
      expect(centerSideOffset(60, 78)).assertEqual(0);
    });
  });
}
