import { describe, it, expect } from '@ohos/hypium';
import { mapHttpError, mapResponseError, SAD_PANDA_CODE } from '../../main/ets/network/HttpErrorMapping';
import { KOKOMADE_CODE } from '../../main/ets/parser/EhErrorDetector';

export default function httpErrorMappingTest() {
  describe('HttpErrorMapping', () => {
    it('maps_509_to_code_509', 0, () => {
      const err = mapHttpError(509, 'image/gif', 9615);
      expect(err?.code).assertEqual(509);
    });
    it('maps_sad_panda_to_custom_code', 0, () => {
      const err = mapHttpError(200, 'text/html; sadpanda', 0);
      expect(err?.code).assertEqual(SAD_PANDA_CODE);
    });
    it('returns_null_for_ok_html', 0, () => {
      expect(mapHttpError(200, 'text/html', 1234)).assertNull();
    });
    it('mapResponseError_detects_sad_panda_by_real_headers', 0, () => {
      const err = mapResponseError(200, 'image/gif', 'inline; filename="sadpanda.jpg"', '9615', '');
      expect(err?.code).assertEqual(SAD_PANDA_CODE);
    });
    it('mapResponseError_detects_kokomade_by_body', 0, () => {
      const err = mapResponseError(200, 'text/html', '', '', '<img src="https://exhentai.org/img/kokomade.jpg">');
      expect(err?.code).assertEqual(KOKOMADE_CODE);
    });
    it('mapResponseError_null_for_ok', 0, () => {
      expect(mapResponseError(200, 'text/html', '', '', '<html>ok</html>')).assertNull();
    });
  });
}
