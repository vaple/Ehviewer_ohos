import { describe, it, expect } from '@ohos/hypium';
import { redact } from '../../main/ets/common/Redact';

export default function redactTest() {
  describe('Redact', () => {
    it('redacts_known_keys_case_insensitive', 0, () => {
      expect(redact('ipb_pass_hash=abc123')).assertEqual('ipb_pass_hash=***');
      expect(redact('IPB_MEMBER_ID: 42')).assertEqual('IPB_MEMBER_ID: ***');
      expect(redact('{"apikey":"deadbeef"}')).assertEqual('{"apikey":"***"}');
      expect(redact('igneous=zzzzzzzz')).assertEqual('igneous=***');
      expect(redact('password=hunter2')).assertEqual('password=***');
    });

    it('keeps_gallery_token_and_plain_text', 0, () => {
      expect(redact('https://e-hentai.org/g/123/abcdef0123/'))
        .assertEqual('https://e-hentai.org/g/123/abcdef0123/');
      expect(redact('token=abcdef0123')).assertEqual('token=abcdef0123');
      expect(redact('parse null gid=123 reason=no #gn')).assertEqual('parse null gid=123 reason=no #gn');
    });

    it('redacts_cookie_header_as_whole_value', 0, () => {
      expect(redact('Cookie: ipb_member_id=1; igneous=zzz')).assertEqual('Cookie: ***');
      expect(redact('authorization: Bearer abc.def')).assertEqual('authorization: ***');
    });

    it('redacts_cookie_when_header_is_mid_line', 0, () => {
      expect(redact('headers: cookie: a=1; cf_clearance=b')).assertEqual('headers: cookie: ***');
      expect(redact('cf_clearance=zzz')).assertEqual('cf_clearance=***');
    });

    it('redacts_query_parameters_only', 0, () => {
      expect(redact('GET https://e-hentai.org/x?ipb_pass_hash=zz&page=2'))
        .assertEqual('GET https://e-hentai.org/x?ipb_pass_hash=***&page=2');
    });

    it('redacts_every_line_of_multiline_text', 0, () => {
      expect(redact('a\nipb_pass_hash=1\nb')).assertEqual('a\nipb_pass_hash=***\nb');
    });
  });
}
