/**
 * 星条显示/提交规则（纯函数，行为即断言；见 `GalleryRating.test`）。
 *
 * 绑平均分时要用独立状态：详情加载时分数从 0 跳到均值会触发 `onChange`，不能当成用户打分。
 * 现行规则：回调值 == 当前显示值 ⇒ 程序化赋值（0→均值、提交后回填）→ 忽略；
 * 用户点选必然与显示值不同 → 提交。
 */

/** 星条显示值：打过分为我的分，否则为平均分。 */
export function displayRatingFor(myRating: number, rating: number): number {
  return myRating > 0 ? myRating : rating;
}

/** 星条 `onChange(picked)` 是否应提交评分。 */
export function shouldSubmitRating(displayed: number, picked: number): boolean {
  return picked !== displayed;
}
