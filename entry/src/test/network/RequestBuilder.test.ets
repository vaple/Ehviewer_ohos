import { describe, it, expect } from '@ohos/hypium';
import { RequestBuilder } from '../../main/ets/network/RequestBuilder';

export default function requestBuilderTest() {
  describe('RequestBuilder', () => {
    it('defaultHeaders_has_mozilla_user_agent', 0, () => {
      const ua: string = RequestBuilder.defaultHeaders()['User-Agent'];
      expect(ua.includes('Mozilla')).assertTrue();
    });
    it('cookieHeader_joins_with_semicolon_space', 0, () => {
      const cookies: Record<string, string> = { 'a': '1', 'b': '2' };
      expect(RequestBuilder.cookieHeader(cookies)).assertEqual('a=1; b=2');
    });
    it('cookieHeader_empty_returns_empty_string', 0, () => {
      const empty: Record<string, string> = {};
      expect(RequestBuilder.cookieHeader(empty)).assertEqual('');
    });
  });
}
