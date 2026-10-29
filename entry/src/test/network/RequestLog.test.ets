import { describe, it, expect } from '@ohos/hypium';
import { requestLine } from '../../main/ets/network/RequestLog';

export default function requestLogTest() {
  describe('RequestLog', () => {
    it('formats_status_bytes_and_content_type', 0, () => {
      const line: string = requestLine('GET', 'https://e-hentai.org/g/123/abcdef/', 200, 33154, 87, 'text/html');
      expect(line.indexOf('GET https://e-hentai.org/g/123/abcdef/')).assertEqual(0);
      expect(line.indexOf('→ 200 33154B 87ms text/html') > 0).assertTrue();
    });

    it('redacts_credentials_in_url', 0, () => {
      const line: string = requestLine('GET', 'https://e-hentai.org/x?ipb_pass_hash=zz&page=2', 200, 10, 5, 'text/html');
      expect(line.indexOf('ipb_pass_hash=***') > 0).assertTrue();
      expect(line.indexOf('page=2') > 0).assertTrue();
    });
  });
}
