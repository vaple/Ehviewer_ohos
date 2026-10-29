import { describe, it, expect } from '@ohos/hypium';
import { LOG_LINE_MAX_BYTES, logLine, stamp, truncateUtf8, utf8Length } from '../../main/ets/service/LogFormat';

export default function logFormatTest() {
  describe('LogFormat', () => {
    it('stamp_pads_every_field', 0, () => {
      const ts: number = new Date(2026, 9, 27, 9, 5, 7, 42).getTime();
      expect(stamp(ts)).assertEqual('2026-10-27 09:05:07.042');
    });

    it('utf8 length counts bytes not code units', 0, () => {
      expect(utf8Length('abc')).assertEqual(3);
      expect(utf8Length('中文')).assertEqual(6);
      expect(utf8Length('😀')).assertEqual(4);
    });

    it('short text passes through untouched', 0, () => {
      expect(truncateUtf8('中文abc', 64)).assertEqual('中文abc');
    });

    it('truncates_on_char_boundary_and_marks_dropped', 0, () => {
      // '中文' = 6 字节，加 'a' = 7 字节刚好到上限；'bc' 被丢掉 → 标记 (+2)
      expect(truncateUtf8('中文abc', 7)).assertEqual('中文a…(+2)');
    });

    it('log line replaces newlines with a visible marker', 0, () => {
      const ts: number = new Date(2026, 9, 27, 9, 5, 7, 42).getTime();
      expect(logLine(ts, 'I', 'Http', 'a\nb')).assertEqual('2026-10-27 09:05:07.042 I Http: a⏎b');
    });

    it('log line never exceeds the byte budget by more than the marker', 0, () => {
      const ts: number = new Date(2026, 9, 27, 9, 5, 7, 42).getTime();
      const line: string = logLine(ts, 'E', 'Detail', 'x'.repeat(3000));
      expect(utf8Length(line) <= LOG_LINE_MAX_BYTES + 12).assertTrue();
      expect(line.indexOf('…(+') > 0).assertTrue();
    });
  });
}
