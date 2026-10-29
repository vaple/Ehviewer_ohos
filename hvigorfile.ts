import { appTasks, OhosPluginId, OhosAppContext } from '@ohos/hvigor-ohos-plugin';
import { getNode, hvigor, HvigorNode } from '@ohos/hvigor';

/**
 * versionCode 由 AppScope/app.json5 的 versionName 在**构建期**算出并注入，
 * versionName 是唯一真源；磁盘上 app.json5 的 versionCode 只作可读性参考，
 * 每次构建都会被这里覆盖（所以不用手工维护，也不会写回源文件）。
 *
 *   versionCode = major * 1_000_000 + minor * 10_000 + patch * 100
 *   1.0.0 -> 1000000 / 1.0.1 -> 1000100 / 1.2.3 -> 1020300
 */
const SEMVER = /^(\d+)\.(\d+)\.(\d+)$/;

function versionCodeOf(versionName: string): number {
  const matched = SEMVER.exec(versionName);
  if (!matched) {
    throw new Error(
      `versionName 必须是 x.y.z 形式，当前是 ${JSON.stringify(versionName)}（AppScope/app.json5）。` +
      ' versionCode 由它算出，构建不会猜版本。'
    );
  }
  const major = Number(matched[1]);
  const minor = Number(matched[2]);
  const patch = Number(matched[3]);
  if (minor > 99 || patch > 99) {
    throw new Error(`versionName 的 minor/patch 不能超过 99，当前是 ${versionName}（否则公式会串位）`);
  }
  return major * 1_000_000 + minor * 10_000 + patch * 100;
}

hvigor.nodesEvaluated(() => {
  const node: HvigorNode = getNode(__filename);
  const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const appJson = appContext.getAppJsonOpt();
  const versionName = appJson.app.versionName;
  const versionCode = versionCodeOf(versionName);
  if (appJson.app.versionCode !== versionCode) {
    console.log(`[version] versionName ${versionName} -> versionCode ${appJson.app.versionCode} => ${versionCode}`);
    appJson.app.versionCode = versionCode;
    appContext.setAppJsonOpt(appJson);
  }
});

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
