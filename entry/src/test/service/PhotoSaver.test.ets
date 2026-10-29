import { describe, it, expect } from '@ohos/hypium';
import { detectImageExt } from '../../main/ets/service/PhotoSaver';

export default function photoSaverTest() {
  describe('PhotoSaver', () => {
    it('detects_format_by_magic_bytes', 0, () => {
      expect(detectImageExt(new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0]))).assertEqual('jpg');
      expect(detectImageExt(new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))).assertEqual('png');
      expect(detectImageExt(new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]))).assertEqual('gif');
      const webp = new Uint8Array(
        [0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]);
      expect(detectImageExt(webp)).assertEqual('webp');
    });

    it('unknown_magic_throws', 0, () => {
      let thrown: boolean = false;
      try {
        detectImageExt(new Uint8Array([0x00, 0x01, 0x02, 0x03]));
      } catch (e) {
        thrown = true;
      }
      expect(thrown).assertTrue();
    });
  });
}
