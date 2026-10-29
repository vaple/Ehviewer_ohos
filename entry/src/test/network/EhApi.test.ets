import { describe, it, expect } from '@ohos/hypium';
import { buildRateBody, clampRating, parseRateResult, buildCommentForm } from '../../main/ets/network/EhApi';

export default function ehApiTest() {
  describe('EhApi', () => {
    it('rate_body_has_source_fields', 0, () => {
      const body: Record<string, string | number> = buildRateBody(123, 'abc123', 456, 'tok', 4.5);
      expect(body['method']).assertEqual('rategallery');
      expect(body['apiuid']).assertEqual(123);
      expect(body['apikey']).assertEqual('abc123');
      expect(body['gid']).assertEqual(456);
      expect(body['token']).assertEqual('tok');
      expect(body['rating']).assertEqual(9);
    });

    it('clamp_rating_halves_to_1_10', 0, () => {
      expect(clampRating(0)).assertEqual(1);
      expect(clampRating(5.7)).assertEqual(10);
      expect(clampRating(2.3)).assertEqual(5);
      expect(clampRating(4.5)).assertEqual(9);
    });

    it('rate_result_parses_avg_and_count', 0, () => {
      const r = parseRateResult('{"rating_avg":4.27,"rating_cnt":123}');
      expect(r !== null).assertTrue();
      expect(r?.rating ?? 0).assertEqual(4.27);
      expect(r?.count ?? 0).assertEqual(123);
      expect(parseRateResult('not json')).assertEqual(null);
    });

    it('comment_form_uses_source_field_name', 0, () => {
      const form: Record<string, string> = buildCommentForm('hello');
      expect(form['commenttext_new']).assertEqual('hello');
    });
  });
}
