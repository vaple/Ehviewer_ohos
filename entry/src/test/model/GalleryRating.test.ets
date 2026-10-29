import { describe, it, expect } from '@ohos/hypium';
import { displayRatingFor, shouldSubmitRating } from '../../main/ets/model/GalleryRating';

export default function galleryRatingTest() {
  describe('GalleryRating', () => {
    it('display_uses_average_before_my_rating', 0, () => {
      expect(displayRatingFor(0, 4.25)).assertEqual(4.25);
    });

    it('display_prefers_my_rating_after_vote', 0, () => {
      expect(displayRatingFor(3.5, 4.25)).assertEqual(3.5);
    });

    it('programmatic_set_is_ignored', 0, () => {
      // 详情 0 → 均值 4.5 的跳变：回调值 == 显示值 → 不提交。
      expect(shouldSubmitRating(4.5, 4.5)).assertFalse();
      // 提交成功后回填我的分同样是程序化赋值。
      expect(shouldSubmitRating(3, 3)).assertFalse();
    });

    it('user_pick_submits', 0, () => {
      expect(shouldSubmitRating(4.5, 3)).assertTrue();
      expect(shouldSubmitRating(4.5, 4)).assertTrue();
    });
  });
}
