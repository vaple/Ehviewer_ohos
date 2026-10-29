import { describe, it, expect } from '@ohos/hypium';
import { Html } from '../../main/ets/parser/Html';
import { GALLERY_LIST_HTML } from '../fixtures/galleryList';

export default function htmlTest() {
  describe('Html', () => {
    it('select_by_tag_name_returns_all_matches', 0, () => {
      const root = Html.parse(GALLERY_LIST_HTML);
      expect(Html.select(root, 'a').length).assertEqual(3);
    });
    it('text_returns_node_text', 0, () => {
      const root = Html.parse(GALLERY_LIST_HTML);
      const first = Html.select(root, 'a')[0];
      expect(Html.text(first)).assertEqual('One');
    });
    it('attr_returns_value_or_null', 0, () => {
      const root = Html.parse(GALLERY_LIST_HTML);
      const first = Html.select(root, 'a')[0];
      expect(Html.attr(first, 'href')).assertEqual('/g/1/abc/');
      expect(Html.attr(first, 'missing')).assertNull();
    });
    it('select_by_id', 0, () => {
      const root = Html.parse(GALLERY_LIST_HTML);
      expect(Html.select(root, '#link2').length).assertEqual(1);
    });
    it('select_by_class', 0, () => {
      const root = Html.parse(GALLERY_LIST_HTML);
      expect(Html.select(root, '.other').length).assertEqual(2);
    });
  });
}
