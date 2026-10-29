import { describe, it, expect } from '@ohos/hypium';
import { detectHtmlError, detectSadPanda, KOKOMADE_CODE, PINING_CODE, pageText } from '../../main/ets/parser/EhErrorDetector';

export default function ehErrorDetectorTest() {
  describe('EhErrorDetector', () => {
    it('sad_panda_by_headers', 0, () => {
      expect(detectSadPanda('inline; filename="sadpanda.jpg"', 'image/gif', '9615')).assertTrue();
      expect(detectSadPanda('inline', 'text/html', '100')).assertFalse();
      expect(detectSadPanda(undefined, undefined, undefined)).assertFalse();
    });

    it('kokomade_by_body', 0, () => {
      const body: string = '<html><body><img src="https://exhentai.org/img/kokomade.jpg"/></body></html>';
      expect(detectHtmlError(body)?.code).assertEqual(KOKOMADE_CODE);
    });

    it('pining_by_body', 0, () => {
      const body: string = '<html><body><p>This gallery is pining for the fjords.</p></body></html>';
      expect(detectHtmlError(body)?.code).assertEqual(PINING_CODE);
    });

    it('normal_body_returns_null', 0, () => {
      expect(detectHtmlError('<html><body>ok</body></html>')).assertNull();
      expect(detectHtmlError('')).assertNull();
    });

    it('page_text_keeps_site_wording_verbatim', 0, () => {
      const body: string = '<html><head><title>509</title></head><body>' +
        '<div>You are currently at 4321 towards your account limit of 5000.</div>' +
        '<p>more text</p></body></html>';
      expect(pageText(body).startsWith('509 · You are currently at 4321 towards your account limit of 5000.'))
        .assertTrue();
    });

    it('page_text_without_title_and_empty_body', 0, () => {
      expect(pageText('<html><body><p>hello   world</p></body></html>')).assertEqual('hello world');
      expect(pageText('')).assertEqual('');
    });
  });
}
