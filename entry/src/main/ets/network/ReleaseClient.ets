/**
 * 更新检查的纯逻辑：tag 解析 / 版本比较 / release JSON 解析 / 两源择优。
 *
 * 设计要点：
 * - 只做字符串与 JSON 处理，**不碰网络、不碰设备 API**（本地单测直接跑）。
 * - 两个源的 latest 响应字段同构（GitHub API 与 GitCode v5 兼容接口都返回
 *   `tag_name` / `body` / `prerelease` / `assets[].name` / `assets[].browser_download_url`），
 *   所以一个解析函数带 `source` 入参就够了，不为两站各写一份。
 * - 安装包资产按 `name` 以 `.hap` 结尾挑，**不写死文件名**（GitHub 是 `ehviewer-x.y.z.hap`、
 *   GitCode 是 `ehv-x.y.z.hap`，将来还可能改）。
 */

import { Logger } from '../common/Logger';
import { HttpClient, HttpResponse } from './HttpClient';

/** 发布来源：下载地址优先 GitCode（国内可用性更好）。 */
export enum ReleaseSource {
  GITHUB = 0,
  GITCODE = 1
}

/** 单个源解析出的 release 信息。 */
export interface ReleaseInfo {  source: ReleaseSource;
  /** tag 原文，如 `v1.1.0`（展示用）。 */
  tag: string;
  /** 去前缀后的版本号，如 `1.1.0`（比较用）。 */
  version: string;
  /** release 说明原文（不做 Markdown 处理）。 */
  notes: string;
  /** 安装包资产原名（保存面板的默认文件名）。 */
  hapName: string;
  /** 安装包下载地址。 */
  hapUrl: string;
}

/** 择优结果：`chosen` 是要展示/下载的那个，`mirrors` 只含与它**同版本**的源（GitCode 在前）。 */
export interface ReleasePick {
  chosen: ReleaseInfo;
  mirrors: ReleaseInfo[];
}

/** latest 响应里的资产（两站同构；只取用得上的字段）。 */
interface ReleaseAssetWire {
  name?: string;
  browser_download_url?: string;
}

/** latest 响应（两站同构）。 */
interface ReleaseWire {
  tag_name?: string;
  body?: string;
  prerelease?: boolean;
  assets?: ReleaseAssetWire[];
}

/**
 * tag → 版本号：只去 `v` / `V` 前缀，其余必须全是「数字 + 点」。
 * `release-1.0`、`1.0.0-beta`、空串一律视为无法解析（该源作废，不猜）。
 */
export function parseTagName(tag: string): string | undefined {
  let text: string = tag.trim();
  if (text.length > 0 && (text.charAt(0) === 'v' || text.charAt(0) === 'V')) {
    text = text.substring(1);
  }
  if (text.length === 0) {
    return undefined;
  }
  const parts: string[] = text.split('.');
  for (let i: number = 0; i < parts.length; i++) {
    const part: string = parts[i];
    if (part.length === 0) {
      return undefined;
    }
    for (let j: number = 0; j < part.length; j++) {
      const code: number = part.charCodeAt(j);
      if (code < 48 || code > 57) {
        return undefined;
      }
    }
  }
  return text;
}

/**
 * 版本比较：逐段按数值比，缺段按 `0`（`1.2` == `1.2.0`）。
 * 入参必须是 `parseTagName` 校验过的字符串（含非数字段时按 `0` 处理，不做二次报错）。
 */
export function compareVersion(a: string, b: string): number {
  const left: string[] = a.split('.');
  const right: string[] = b.split('.');
  const count: number = Math.max(left.length, right.length);
  for (let i: number = 0; i < count; i++) {
    const x: number = i < left.length ? Number(left[i]) : 0;
    const y: number = i < right.length ? Number(right[i]) : 0;
    if (x > y) {
      return 1;
    }
    if (x < y) {
      return -1;
    }
  }
  return 0;
}

/** 远端是否比本地新（任一版本无法解析 → `false`，不提示）。 */
export function isNewer(latest: string, current: string): boolean {
  const remote: string | undefined = parseTagName(latest);
  const local: string | undefined = parseTagName(current);
  if (remote === undefined || local === undefined) {
    return false;
  }
  return compareVersion(remote, local) > 0;
}

/** 挑安装包资产：`name` 以 `.hap` 结尾且下载地址非空（`.hap.sha256`、源码 zip 都不算）。 */
function pickHapAsset(wire: ReleaseWire): ReleaseAssetWire | undefined {
  const assets: ReleaseAssetWire[] | undefined = wire.assets;
  if (assets === undefined) {
    return undefined;
  }
  for (let i: number = 0; i < assets.length; i++) {
    const asset: ReleaseAssetWire = assets[i];
    const name: string | undefined = asset.name;
    const url: string | undefined = asset.browser_download_url;
    if (name === undefined || url === undefined || url.length === 0) {
      continue;
    }
    if (name.endsWith('.hap')) {
      return asset;
    }
  }
  return undefined;
}

/**
 * latest 响应体 → `ReleaseInfo`。
 * 预发布 / tag 无法解析 / 没有 `.hap` 资产 / JSON 不合法 → `undefined`（调用方按「该源不可用」处理）。
 */
export function parseRelease(body: string, source: ReleaseSource): ReleaseInfo | undefined {
  let wire: ReleaseWire;
  try {
    wire = JSON.parse(body) as ReleaseWire;
  } catch (e) {
    return undefined;
  }
  if (wire.prerelease === true) {
    return undefined;
  }
  const tag: string | undefined = wire.tag_name;
  if (tag === undefined) {
    return undefined;
  }
  const version: string | undefined = parseTagName(tag);
  if (version === undefined) {
    return undefined;
  }
  const asset: ReleaseAssetWire | undefined = pickHapAsset(wire);
  if (asset === undefined) {
    return undefined;
  }
  const notes: string = wire.body === undefined ? '' : wire.body;
  const hapName: string = asset.name === undefined ? '' : asset.name;
  const hapUrl: string = asset.browser_download_url === undefined ? '' : asset.browser_download_url;
  return { source: source, tag: tag, version: version, notes: notes, hapName: hapName, hapUrl: hapUrl };
}

/**
 * 两源择优：取版本高者；**版本相同取 GitCode**（优先下载源）。
 * `mirrors` 只保留与 `chosen` 同版本的源——不同版本的包内容不同，拿另一个源当"备用下载地址"
 * 只会下成另一个版本，不属于回退。
 */
export function pickBetter(github: ReleaseInfo | undefined, gitcode: ReleaseInfo | undefined): ReleasePick | undefined {
  if (github !== undefined && gitcode !== undefined) {
    const cmp: number = compareVersion(gitcode.version, github.version);
    if (cmp > 0) {
      const only: ReleaseInfo[] = [gitcode];
      return { chosen: gitcode, mirrors: only };
    }
    if (cmp === 0) {
      const both: ReleaseInfo[] = [gitcode, github];
      return { chosen: gitcode, mirrors: both };
    }
    const only: ReleaseInfo[] = [github];
    return { chosen: github, mirrors: only };
  }
  if (gitcode !== undefined) {
    const only: ReleaseInfo[] = [gitcode];
    return { chosen: gitcode, mirrors: only };
  }
  if (github !== undefined) {
    const only: ReleaseInfo[] = [github];
    return { chosen: github, mirrors: only };
  }
  return undefined;
}

/** latest 接口（两源各一）：GitCode 国内可用性好，下载优先走它。 */
const GITHUB_LATEST: string = 'https://api.github.com/repos/vaple/Ehviewer_ohos/releases/latest';
const GITCODE_LATEST: string = 'https://api.gitcode.com/api/v5/repos/u012939801/Ehviewer_ohos/releases/latest';
/** 检查更新的超时：启动路径上的请求，宁可失败也不能拖慢首帧。 */
const CHECK_TIMEOUT_MS: number = 5000;

/**
 * 取两源的 latest release：并行请求，任一成功即用（取版本高者；同版本取 GitCode）。
 * 单个源失败只记日志，不抛给调用方。
 */
export class ReleaseClient {
  private http: HttpClient;

  constructor(http: HttpClient) {
    this.http = http;
  }

  async latest(): Promise<ReleasePick | undefined> {
    const both: (ReleaseInfo | undefined)[] = await Promise.all([
      this.fetchOne(GITHUB_LATEST, ReleaseSource.GITHUB),
      this.fetchOne(GITCODE_LATEST, ReleaseSource.GITCODE)
    ]);
    return pickBetter(both[0], both[1]);
  }

  private async fetchOne(url: string, source: ReleaseSource): Promise<ReleaseInfo | undefined> {
    try {
      const resp: HttpResponse = await this.http.get(url, {
        headers: { 'Accept': 'application/json' },
        timeoutMs: CHECK_TIMEOUT_MS
      });
      const info: ReleaseInfo | undefined = parseRelease(resp.body, source);
      if (info === undefined) {
        Logger.error('Update', `release parse failed: source=${source}`);
      }
      return info;
    } catch (e) {
      Logger.error('Update', `release fetch failed: source=${source}: ${e}`);
      return undefined;
    }
  }
}
