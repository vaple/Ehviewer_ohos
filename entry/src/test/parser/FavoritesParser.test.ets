import { describe, it, expect } from '@ohos/hypium';
import { buildAddFavForm } from '../../main/ets/network/EhApi';
import { parseFavMeta } from '../../main/ets/parser/FavoritesParser';

const FP_TWO_CATS: string = '<div>' +
  '<div class="fp" onclick="document.location=\'https://exhentai.org/favorites.php?favcat=0\'">' +
  '<div style="font-weight:bold">46</div>' +
  '<div class="i" title="Favorites 0"></div>' +
  '<div style="float:left">Favorites 0</div></div>' +
  '<div class="fp" onclick="document.location=\'https://exhentai.org/favorites.php?favcat=1\'">' +
  '<div style="font-weight:bold">0</div>' +
  '<div class="i" title="Favorites 1"></div>' +
  '<div style="float:left"></div></div>' +
  '<div class="fp fps" onclick="document.location=\'https://exhentai.org/favorites.php\'">Show All Favorites</div>' +
  '<div>Order: <select><option value="p">Published Time</option>' +
  '<option value="f" selected="selected">Favorited Time</option></select></div></div>';

export default function favoritesParserTest() {
  describe('FavoritesParser', () => {
    it('buildAddFavForm_fields', 0, () => {
      const form: Record<string, string> = buildAddFavForm(3);
      expect(form['favcat']).assertEqual('3');
      expect(form['favnote']).assertEqual('');
      expect(form['submit']).assertEqual('Apply Changes');
      expect(form['update']).assertEqual('1');
      expect(buildAddFavForm(-1)['favcat']).assertEqual('favdel');
    });

    it('buildAddFavForm_invalid_throws', 0, () => {
      let thrown: boolean = false;
      try {
        buildAddFavForm(10);
      } catch (e) {
        thrown = true;
      }
      expect(thrown).assertTrue();
    });

    it('parseFavMeta_cats_counts_order', 0, () => {
      const meta = parseFavMeta(FP_TWO_CATS);
      expect(meta.cats.length).assertEqual(2);
      expect(meta.cats[0]).assertEqual('Favorites 0');
      expect(meta.cats[1]).assertEqual('Favorites 1');
      expect(meta.counts[0]).assertEqual(46);
      expect(meta.counts[1]).assertEqual(0);
      expect(meta.order).assertEqual('f');
    });

    it('parseFavMeta_empty', 0, () => {
      const meta = parseFavMeta('<html><body>no fav here</body></html>');
      expect(meta.cats.length).assertEqual(0);
      expect(meta.counts.length).assertEqual(0);
      expect(meta.order).assertEqual('');
    });
  });
}
