import { describe, it, expect } from '@ohos/hypium';
import { parseCookieString } from '../../main/ets/parser/CookieStringParser';

export default function cookieStringParserTest() {
  describe('CookieStringParser', () => {
    it('parses_multiple_pairs', 0, () => {
      const m: Record<string, string> = parseCookieString('ipb_member_id=1; ipb_pass_hash=abc; igneous=xyz');
      expect(m['ipb_member_id']).assertEqual('1');
      expect(m['ipb_pass_hash']).assertEqual('abc');
      expect(m['igneous']).assertEqual('xyz');
    });

    it('ignores_malformed_pairs', 0, () => {
      const m: Record<string, string> = parseCookieString('a=1; garbage; =x; b=2');
      expect(m['a']).assertEqual('1');
      expect(m['b']).assertEqual('2');
      expect(m['garbage']).assertEqual(undefined);
    });

    it('empty_returns_empty', 0, () => {
      expect(Object.keys(parseCookieString('')).length).assertEqual(0);
    });

    it('parses_newline_separated_pairs', 0, () => {
      const m: Record<string, string> = parseCookieString(
        'ipb_member_id=1234567\nipb_pass_hash=deadbeefdeadbeefdeadbeefdeadbeef\nigneous=fakeigneous0000000\n');
      expect(m['ipb_member_id']).assertEqual('1234567');
      expect(m['ipb_pass_hash']).assertEqual('deadbeefdeadbeefdeadbeefdeadbeef');
      expect(m['igneous']).assertEqual('fakeigneous0000000');
    });

    it('parses_crlf_and_cookie_header_prefix', 0, () => {
      const m: Record<string, string> = parseCookieString(
        'Cookie: ipb_member_id=1\r\nipb_pass_hash=abc\r\nigneous=xyz');
      expect(m['ipb_member_id']).assertEqual('1');
      expect(m['ipb_pass_hash']).assertEqual('abc');
      expect(m['igneous']).assertEqual('xyz');
    });
  });
}
