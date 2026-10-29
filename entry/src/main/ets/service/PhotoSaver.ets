import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { Logger } from '../common/Logger';
import { detectImageExt } from './ImageExt';

export { detectImageExt };

/**
 * 把 `ImageStore` 的缓存文件（`file://` URI）存进相册。
 * 调用方须持有 `SaveButton` 给的临时授权；失败直接抛（调用方记日志 + 人话），不做任何降级。
 */
export class PhotoSaver {
  static async saveToGallery(context: common.Context, srcUri: string): Promise<void> {
    const srcPath: string = new fileUri.FileUri(srcUri).path;
    const buf: ArrayBuffer = new ArrayBuffer(fs.statSync(srcPath).size);
    const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
    try {
      let offset: number = 0;
      while (offset < buf.byteLength) {
        const read: number = fs.readSync(src.fd, buf, { offset: offset });
        if (read <= 0) {
          break;
        }
        offset += read;
      }
      if (offset !== buf.byteLength) {
        throw new Error(`short read ${offset}/${buf.byteLength}`);
      }
    } finally {
      fs.closeSync(src.fd);
    }
    const ext: string = detectImageExt(new Uint8Array(buf));
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const destUri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, ext);
    const out = await fs.open(destUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      await fs.write(out.fd, buf);
    } catch (e) {
      // 半成品资产尽力清理；清理失败只追加日志，不掩盖原错。
      try {
        await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(context, [destUri]);
      } catch (cleanup) {
        Logger.error('Reader', `cleanup ${destUri} failed: ${cleanup}`);
      }
      throw new Error(`gallery write failed: ${e}`);
    } finally {
      await fs.close(out.fd);
    }
    // 落盘后打一条：方便以后排查「相册没刷新」时确认资产确实建好、字节数正确。
    Logger.info('Reader',
      `saved to gallery: ${destUri} (${buf.byteLength} bytes, ${ext})`);
  }
}
