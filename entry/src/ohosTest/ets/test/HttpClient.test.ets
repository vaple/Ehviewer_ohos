import { describe, it, expect } from '@ohos/hypium';
import { RcpHttpClient } from '../../../main/ets/network/RcpHttpClient';
import { HttpResponse } from '../../../main/ets/network/HttpClient';

export default function httpClientTest() {
  describe('HttpClient', () => {
    it('get_ehentai_root_returns_200', 0, async () => {
      const client = new RcpHttpClient();
      const resp: HttpResponse = await client.get('https://e-hentai.org/');
      expect(resp.status).assertEqual(200);
      expect(resp.body.length > 0).assertTrue();
    });
  });
}
