import { describe, it, expect } from '@ohos/hypium';
import { isAllSelected, submittedKeyword, toggleGid } from '../../main/ets/common/FavList';

export default function favoritesBatchTest() {
  describe('FavoritesBatch', () => {
    it('toggleGid_adds_and_removes', 0, () => {
      const added: number[] = toggleGid([], 7);
      expect(added.length).assertEqual(1);
      expect(added[0]).assertEqual(7);
      expect(toggleGid([7], 7).length).assertEqual(0);
      const kept: number[] = toggleGid([7, 8], 7);
      expect(kept.length).assertEqual(1);
      expect(kept[0]).assertEqual(8);
    });

    it('submittedKeyword_prefers_submit_value_over_draft', 0, () => {
      // 中文输入法组词：draft 里是拼音，onSubmit 给的是最终汉字 → 必须用后者。
      expect(submittedKeyword('催眠', 'cuimian')).assertEqual('催眠');
      // 英文没有组词过程，两者一致（回归保护）。
      expect(submittedKeyword('chinese', 'chinese')).assertEqual('chinese');
      // 去掉首尾空白。
      expect(submittedKeyword('  a b  ', '')).assertEqual('a b');
    });

    it('submittedKeyword_falls_back_to_draft', 0, () => {
      // 个别 ROM 的搜索按钮回调可能不给值：这时退回输入框里的草稿。
      expect(submittedKeyword('', '催眠')).assertEqual('催眠');
      expect(submittedKeyword('', '')).assertEqual('');
    });

    it('isAllSelected_requires_non_empty', 0, () => {
      expect(isAllSelected([], 0)).assertFalse();
      expect(isAllSelected([], 5)).assertFalse();
      expect(isAllSelected([1, 2], 5)).assertFalse();
      expect(isAllSelected([1, 2, 3], 3)).assertTrue();
    });
  });
}
