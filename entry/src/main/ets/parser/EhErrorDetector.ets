import { AppError } from '../common/AppError';

/** 错误页判据（与上游 Android 版 EhViewer EhEngine / GalleryDetailParser / TopListParser 一致）。 */
export const KOKOMADE_MARKER: string = 'https://exhentai.org/img/kokomade.jpg';
export const PINING_MARKER: string = '<p>This gallery is pining for the fjords.</p>';
export const NO_HATH_CLIENT_MARKER: string =
  'You must have a H@H client assigned to your account to use this feature.';

export const KOKOMADE_CODE: number = -3;
export const PINING_CODE: number = -4;
export const NO_HATH_CLIENT_CODE: number = -5;

const SAD_PANDA_DISPOSITION: string = 'inline; filename="sadpanda.jpg"';
const SAD_PANDA_TYPE: string = 'image/gif';
const SAD_PANDA_LENGTH: string = '9615';

/** Sad Panda 由**响应头**判定（上游 Android 版 EhViewer `EhEngine.doThrowException`）。 */
export function detectSadPanda(contentDisposition: string | undefined, contentType: string | undefined,
  contentLength: string | undefined): boolean {
  return contentDisposition === SAD_PANDA_DISPOSITION
    && contentType === SAD_PANDA_TYPE
    && contentLength === SAD_PANDA_LENGTH;
}

/** 由**响应体**判定站点错误页；正常页返回 `null`。 */export function detectHtmlError(body: string | null | undefined): AppError | null {
  if (body === null || body === undefined || body.length === 0) {
    return null;
  }
  if (body.includes(KOKOMADE_MARKER)) {
    return new AppError(KOKOMADE_CODE, 'kokomade');
  }
  if (body.includes(PINING_MARKER)) {
    return new AppError(PINING_CODE, 'pining for the fjords');
  }
  if (body.includes(NO_HATH_CLIENT_MARKER)) {
    return new AppError(NO_HATH_CLIENT_CODE, 'No H@H client');
  }
  return null;
}

/** 透传给用户的文字上限（超长截断，避免把整页塞进一行提示）。 */
const PAGE_TEXT_MAX: number = 240;

/** 去标签 + 折叠空白（HTML 实体只处理最常见的 `&nbsp;`，不做完整解码）。 */
function collapse(html: string): string {
  return html.replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * 站点回来的**可见文字**：`<title> · 正文`，去掉标签、折叠空白、截断。
 *
 * **不做任何语义判断**——不挑「哪句是配额句」，不翻译、不改写：
 * 站点说什么，用户就看到什么（`You are currently at 4321 towards your account limit of 5000.` 原样保留）。
 */
export function pageText(body: string): string {
  if (body.length === 0) {
    return '';
  }
  const titleMatch: RegExpMatchArray | null = body.match(new RegExp('<title[^>]*>([\\s\\S]*?)</title>', 'i'));
  const title: string = titleMatch === null ? '' : collapse(titleMatch[1]);
  const rest: string = body
    .replace(new RegExp('<head[\\s\\S]*?</head>', 'gi'), ' ')
    .replace(new RegExp('<script[\\s\\S]*?</script>', 'gi'), ' ')
    .replace(new RegExp('<style[\\s\\S]*?</style>', 'gi'), ' ');
  const text: string = collapse(rest);
  let out: string = title.length > 0 && text.length > 0 ? `${title} · ${text}` : `${title}${text}`;
  if (out.length > PAGE_TEXT_MAX) {
    out = `${out.substring(0, PAGE_TEXT_MAX)}…`;
  }
  return out;
}
