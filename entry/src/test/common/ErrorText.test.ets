import { describe, it, expect } from '@ohos/hypium';
import { errorText } from '../../main/ets/common/ErrorText';
import { AppError } from '../../main/ets/common/AppError';
import { KOKOMADE_CODE, NO_HATH_CLIENT_CODE, PINING_CODE } from '../../main/ets/parser/EhErrorDetector';

export default function errorTextTest() {
  describe('ErrorText', () => {
    it('passes_app_error_message_through_verbatim', 0, () => {
      // 站点原文（`mapResponseError` 把 body 的可见文字塞进 message）一字不改地显示。
      expect(errorText(new AppError(509, 'You are currently at 4321 towards your account limit of 5000')))
        .assertEqual('You are currently at 4321 towards your account limit of 5000');
      expect(errorText(new AppError(403, 'Forbidden'))).assertEqual('Forbidden');
    });

    it('passes_plain_error_message_through', 0, () => {
      expect(errorText(new Error("Couldn't resolve host name"))).assertEqual("Couldn't resolve host name");
    });

    it('translates_only_site_jargon', 0, () => {
      expect(errorText(new AppError(KOKOMADE_CODE, 'kokomade'))).assertEqual('画廊已被删除');
      expect(errorText(new AppError(PINING_CODE, 'pining for the fjords'))).assertEqual('画廊正在归档，稍后再试');
      expect(errorText(new AppError(NO_HATH_CLIENT_CODE, 'No H@H client'))).assertEqual('需要站点分配 H@H 客户端');
    });

    it('parse_failure_carries_reason', 0, () => {
      expect(errorText(null, 'no #gn')).assertEqual('解析失败 (no #gn)');
      expect(errorText(null, '')).assertEqual('出错了，请重试');
    });
  });
}
