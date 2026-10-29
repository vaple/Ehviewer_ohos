import { describe, it, expect } from '@ohos/hypium';
import { HomeParser } from '../../main/ets/parser/HomeParser';
import { HomeStats } from '../../main/ets/model/HomeStats';

/** 站点 `home.php`（My Home）里的图片配额（与上游 Android 版 EhViewer `EhHomeParser` 同源语义）。 */
export default function homeParserTest() {
  describe('HomeParser', () => {
    it('parses_account_limit_wording', 0, () => {
      const html: string =
        '<div class="homebox"><p><strong>Image Limits</strong></p>' +
        '<p>You are currently at <strong>1,234</strong> towards your account limit of <strong>5,000</strong>.</p>' +
        '<p>You can reset your image quota by spending <strong>25</strong> GP.</p></div>';
      const stats: HomeStats = HomeParser.parse(html);
      expect(stats.ok).assertTrue();
      expect(stats.used).assertEqual(1234);
      expect(stats.total).assertEqual(5000);
      expect(stats.resetCost).assertEqual(25);
      expect(stats.ipBased).assertFalse();
    });

    it('parses_legacy_limit_wording', 0, () => {
      const html: string =
        '<div class="homebox"><p>You are currently at <strong>100</strong> towards a limit of ' +
        '<strong>2000</strong>.</p><p>Reset Cost: <strong>10</strong> GP</p></div>';
      const stats: HomeStats = HomeParser.parse(html);
      expect(stats.ok).assertTrue();
      expect(stats.used).assertEqual(100);
      expect(stats.total).assertEqual(2000);
      expect(stats.resetCost).assertEqual(10);
    });

    it('reports_ip_based_when_total_missing', 0, () => {
      const html: string = '<div class="homebox"><p>Image Limits</p>' +
        '<p>Your current IP address has reached its limit.</p></div>';
      const stats: HomeStats = HomeParser.parse(html);
      expect(stats.ok).assertTrue();
      expect(stats.ipBased).assertTrue();
      expect(stats.used).assertEqual(0);
    });

    it('parses_real_ip_based_wording_from_home_php', 0, () => {
      const html: string = '<div class="homebox">' +
        '<p><strong>Image Limits</strong></p>' +
        '<p>Due to widespread usage of bulk downloaders, high-resolution images can be limited. ' +
        'You are currently using IP-based limits. No restrictions are currently in effect. ' +
        'You can get a Bronze Star or the More Pages hathperk to tie image limits to your account.</p>' +
        '</div>';
      const stats: HomeStats = HomeParser.parse(html);
      expect(stats.ok).assertTrue();
      expect(stats.ipBased).assertTrue();
    });

    it('not_logged_in_has_no_stats', 0, () => {
      const stats: HomeStats = HomeParser.parse('<html><body><p>Front page</p></body></html>');
      expect(stats.ok).assertFalse();
    });
  });
}
