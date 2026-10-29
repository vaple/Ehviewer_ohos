import { describe, it, expect } from '@ohos/hypium';
import { toggleGid } from '../../main/ets/ui/FavoritesPage';

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
  });
}
