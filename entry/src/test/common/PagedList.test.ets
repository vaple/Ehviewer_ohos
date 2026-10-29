import { describe, it, expect } from '@ohos/hypium';
import { shouldFetchMore } from '../../main/ets/common/PagedList';

export default function pagedListTest() {
  describe('PagedList', () => {
    it('fetches_when_near_end_with_more', 0, () => {
      expect(shouldFetchMore(25, 20, true, false)).assertTrue();
    });

    it('holds_when_far_from_end', 0, () => {
      expect(shouldFetchMore(25, 10, true, false)).assertFalse();
    });

    it('holds_while_loading', 0, () => {
      expect(shouldFetchMore(25, 24, true, true)).assertFalse();
    });

    it('holds_when_no_more', 0, () => {
      expect(shouldFetchMore(25, 24, false, false)).assertFalse();
    });
  });
}
