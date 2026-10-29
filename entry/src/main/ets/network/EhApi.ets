/**
 * `api.php` JSON 接口的纯函数（源：`EhEngine.rateGallery` + `RateGalleryParser`）。
 * 评分 `rating` 为 0.5 步进的 0.5–5；线上传输整数 `ceil(rating * 2)`（1–10）。
 */
export interface RateResult {
  rating: number;
  count: number;
}

/** 评分钳制 → 线上传输整数（源 `Math.ceil(rating * 2)`）。 */
export function clampRating(rating: number): number {
  const clamped: number = rating < 0.5 ? 0.5 : (rating > 5 ? 5 : rating);
  return Math.ceil(clamped * 2);
}

/** `rategallery` 请求体（字段名照源 `EhEngine`，不许改）。 */
export function buildRateBody(apiUid: number, apiKey: string, gid: number,
  token: string, rating: number): Record<string, string | number> {
  return {
    'method': 'rategallery',
    'apiuid': apiUid,
    'apikey': apiKey,
    'gid': gid,
    'token': token,
    'rating': clampRating(rating)
  };
}

/** `rategallery` 回包 → 新均值 + 总数；解析失败返回 `null`。 */
export function parseRateResult(body: string): RateResult | null {
  try {
    const json: RateWire = JSON.parse(body) as RateWire;
    if (typeof json.rating_avg !== 'number' || typeof json.rating_cnt !== 'number') {
      return null;
    }
    return { rating: json.rating_avg, count: json.rating_cnt };
  } catch (e) {
    return null;
  }
}

/** 发评论表单（源 `EhEngine.commentGallery` 新评论分支字段名，不许改）。 */
export function buildCommentForm(comment: string): Record<string, string> {
  return { 'commenttext_new': comment };
}

/**
 * 收藏增/改/删表单（源 `EhEngine.addFavorites` 字段名，不许改）。
 * `cat` 0–9 进类，`-1` 删除（`favdel`）；其他值抛错（程序员错误，早暴露）。
 */
export function buildAddFavForm(cat: number): Record<string, string> {
  let catStr: string = '';
  if (cat === -1) {
    catStr = 'favdel';
  } else if (cat >= 0 && cat <= 9) {
    catStr = `${cat}`;
  } else {
    throw new Error(`Invalid fav cat: ${cat}`);
  }
  return { 'favcat': catStr, 'favnote': '', 'submit': 'Apply Changes', 'update': '1' };
}

/** 线上回包形状（字段缺失/类型不符时 `parseRateResult` 返回 `null`）。 */
interface RateWire {
  rating_avg?: number;
  rating_cnt?: number;
}
