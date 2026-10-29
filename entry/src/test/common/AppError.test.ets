import { describe, it, expect } from '@ohos/hypium';
import { AppError } from '../../main/ets/common/AppError';

export default function appErrorTest() {
  describe('AppError', () => {
    it('fromHttpStatus_509_sets_code_509', 0, () => {
      expect(AppError.fromHttpStatus(509).code).assertEqual(509);
    });
    it('fromHttpStatus_403_sets_code_403', 0, () => {
      expect(AppError.fromHttpStatus(403).code).assertEqual(403);
    });
    it('fromHttpStatus_unknown_sets_code_minus_one', 0, () => {
      expect(AppError.fromHttpStatus(418).code).assertEqual(-1);
    });
  });
}
