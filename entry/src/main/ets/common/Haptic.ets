import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

/** 已告警过的失败原因：同一种失败只记一次，避免长按反复写日志（振动是小事，不该刷满 diag）。 */
let warned: string = '';

/**
 * 长按识别成功的轻触反馈（长按起菜单、开卡片菜单等）。
 * 用 `VibrateTime`（官方对「点击 / 长按 / 滑动」这类交互反馈的推荐形态；预置效果留给复杂场景），
 * 40ms 够被感知又不拖泥带水。
 * 失败只记日志：设备关掉了振动时系统一律回 `14600101 Device operation failed`
 * （真机实测：时长型 / 预置 `haptic.effect.soft` / 不同 usage 全部同一个错，系统振动记录也停在关闭前），
 * 无马达、权限被收回同理——这些都不该挡住菜单本身。
 */
export function hapticTap(): void {
  vibrator.startVibration(
    { type: 'time', duration: 40 },
    { id: 0, usage: 'unknown' }
  ).catch((e: BusinessError) => {
    const reason: string = `${e.code} ${e.message}`;
    if (reason !== warned) {
      warned = reason;
      Logger.error('Haptic', `vibrate failed: ${reason}`);
    }
  });
}
