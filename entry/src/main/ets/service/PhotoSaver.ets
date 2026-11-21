import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { Logger } from '../common/Logger';
import { detectImageExt } from './ImageExt';

export { detectImageExt };

/**
 * 把 `ImageStore` 的缓存文件（`file://` URI）存进相册。
 *
 * 走官方 `showAssetsCreationDialog`：弹一次系统确认框，用户同意后返回**已授予写权限**的 URI，
 * 直接写入即可。这条路径**不需要** `ohos.permission.WRITE_IMAGEVIDEO`（本应用未申请），
 * 也不依赖安全控件 `SaveButton`——后者没有 `systemMaterial` / `backgroundBlurStyle`，
 * 摆在顶栏会与旁边两颗普通 Button 的材质不一致（`ui/AGENTS.md` #94）。
 *
 * 关于预览：SDK 注释写「源为沙箱路径时保存正常但不显示预览」，**实测不成立**——
 * Mate 80 上弹框能正常显示待保存图片的缩略图（`ui/AGENTS.md` #94）。以实测为准。
 */
export class PhotoSaver {
  /**
   * 保存一页到相册。
   * @returns `true` = 已保存；`false` = 用户在系统弹框里取消（不算错误）。
   * @throws 读取源文件 / 创建资产 / 写入失败时抛出（调用方记日志 + 人话）。
   */
  static async saveViaDialog(context: common.Context, srcUri: string): Promise<boolean> {
    const srcPath: string = new fileUri.FileUri(srcUri).path;
    const size: number = fs.statSync(srcPath).size;
    const buf: ArrayBuffer = new ArrayBuffer(size);
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
    const config: photoAccessHelper.PhotoCreationConfig = {
      title: `ehviewer-${Date.now()}`,
      fileNameExtension: ext,
      photoType: photoAccessHelper.PhotoType.IMAGE
    };
    const dests: string[] = await helper.showAssetsCreationDialog([srcUri], [config]);
    if (dests.length === 0 || dests[0].length === 0) {
      // 用户拒绝：不是错误，不记 error、不打扰用户。
      return false;
    }
    const destUri: string = dests[0];
    const out = await fs.open(destUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      await fs.write(out.fd, buf);
    } catch (e) {
      // 半成品资产尽力清理；清理失败只追加日志，不掩盖原错误。
      try {
        await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(context, [destUri]);
      } catch (cleanup) {
        Logger.error('Reader', `cleanup ${destUri} failed: ${cleanup}`);
      }
      throw new Error(`gallery write failed: ${e}`);
    } finally {
      await fs.close(out.fd);
    }
    Logger.info('Reader', `saved to gallery: ${destUri} (${buf.byteLength} bytes, ${ext})`);
    return true;
  }
}
