import { describe, it, expect } from '@ohos/hypium';
import { GalleryDetailParser } from '../../main/ets/parser/GalleryDetailParser';

const TWO_COMMENTS: string =
  '<div id="cdiv">' +
  '<div class="c1"><div class="c3">Posted on 2026-01-02 03:04 by: &nbsp; <a href="#">alice</a></div>' +
  '<div class="c5"><span>+12</span></div><div class="c6">nice gallery</div></div>' +
  '<div class="c1"><div class="c3">Posted on 2026-01-03 05:06 by: &nbsp; <a href="#">bob</a></div>' +
  '<div class="c6">second</div></div>' +
  '</div>';

export default function galleryCommentsTest() {
  describe('GalleryComments', () => {
    it('parses_two_comments', 0, () => {
      const list = GalleryDetailParser.parseComments(TWO_COMMENTS);
      expect(list.length).assertEqual(2);
      expect(list[0].user).assertEqual('alice');
      expect(list[0].time).assertEqual('2026-01-02 03:04');
      expect(list[0].text).assertEqual('nice gallery');
      expect(list[0].score ?? 0).assertEqual(12);
      expect(list[1].user).assertEqual('bob');
      expect(list[1].score === undefined).assertTrue();
    });

    it('empty_without_cdiv', 0, () => {
      expect(GalleryDetailParser.parseComments('<div>no comments</div>').length).assertEqual(0);
    });

    it('html_in_body_renders_as_plain_text', 0, () => {
      const html: string =
        '<div id="cdiv"><div class="c1">' +
        '<div class="c3">Posted on 2026-01-02 03:04 by: &nbsp; <a href="#">alice</a></div>' +
        '<div class="c6">a<b>bold</b><a href="#">link</a></div></div></div>';
      const list = GalleryDetailParser.parseComments(html);
      expect(list.length).assertEqual(1);
      expect(list[0].text).assertEqual('aboldlink');
      expect(list[0].text.includes('<')).assertFalse();
    });
  });
}
