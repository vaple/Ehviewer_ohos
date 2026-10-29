import { describe, it, expect } from '@ohos/hypium';
import { ReadingDirection, toDisplayIndex, toPage, resolveStartPage } from '../../main/ets/reader/ReaderMode';

export default function readerModeTest() {
  describe('ReaderMode', () => {
    it('rtl_reverses_index', 0, () => {
      expect(toDisplayIndex(0, 5, ReadingDirection.RTL)).assertEqual(4);
      expect(toPage(4, 5, ReadingDirection.RTL)).assertEqual(0);
      expect(toDisplayIndex(2, 5, ReadingDirection.RTL)).assertEqual(2);
    });

    it('ltr_and_vertical_are_identity', 0, () => {
      expect(toDisplayIndex(3, 5, ReadingDirection.LTR)).assertEqual(3);
      expect(toDisplayIndex(3, 5, ReadingDirection.VERTICAL)).assertEqual(3);
      expect(toPage(3, 5, ReadingDirection.LTR)).assertEqual(3);
    });

    it('resolve_start_page_clamps_saved_out_of_range', 0, () => {
      expect(resolveStartPage(7, 37)).assertEqual(7);
      expect(resolveStartPage(0, 37)).assertEqual(0);
      expect(resolveStartPage(-1, 37)).assertEqual(0);
      expect(resolveStartPage(37, 37)).assertEqual(0);
      expect(resolveStartPage(99, 37)).assertEqual(0);
      expect(resolveStartPage(5, 0)).assertEqual(0);
    });
  });
}
