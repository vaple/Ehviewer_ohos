/**
 * 字节数格式化（纯函数，无平台依赖）。
 *
 * 从 `service/CacheManager` 抽出来：`DiagLog` 也要用它，而 `CacheManager` 依赖 `Logger`，
 * 直接互相引用会形成 `Logger → DiagLog → CacheManager → Logger` 的模块环。
 */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0 B';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value: number = bytes;
  let unit: number = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value = value / 1024;
    unit += 1;
  }
  return unit === 0 ? `${Math.round(value)} B` : `${value.toFixed(1)} ${units[unit]}`;
}
