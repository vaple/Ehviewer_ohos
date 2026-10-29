import { describe, it, expect } from '@ohos/hypium';
import { commentDateText, commentScoreText } from '../../main/ets/common/CommentText';

export default function commentTextTest() {
  describe('CommentText', () => {
    it('commentDateText_shortens_site_date', 0, () => {
      // 站点原文（2026-10 实抓）：`Posted on 29 October 2026, 14:53 by:`
      expect(commentDateText('29 October 2026, 14:53')).assertEqual('2026-10-29');
      expect(commentDateText('1 January 2025, 00:05')).assertEqual('2025-01-01');
      expect(commentDateText(' 31 December 2024, 23:59 ')).assertEqual('2024-12-31');
    });

    it('commentDateText_drops_iso_time', 0, () => {
      expect(commentDateText('2026-01-02 03:04')).assertEqual('2026-01-02');
    });

    it('commentDateText_keeps_unknown_text', 0, () => {
      // 认不出来就原样显示，不猜（宁可长，也不能显示错日期）。
      expect(commentDateText('刚刚')).assertEqual('刚刚');
      expect(commentDateText('29 Smarch 2026, 14:53')).assertEqual('29 Smarch 2026, 14:53');
    });

    it('commentScoreText_shows_sign', 0, () => {
      expect(commentScoreText(5)).assertEqual('+5');
      expect(commentScoreText(-3)).assertEqual('-3');
      expect(commentScoreText(0)).assertEqual('0');
      expect(commentScoreText(undefined)).assertEqual('');
    });
  });
}
