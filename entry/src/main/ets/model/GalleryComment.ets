/**
 * 画廊评论（源 `GalleryComment` 子集：投票/编辑能力超出 MVP，只取展示字段）。
 * `time` 为页面原文日期串（不做日期解析，避免失败分支）；`id` 为列表序号（投票/编辑不在本期）。
 */
export interface GalleryComment {
  id: number;
  user: string;
  time: string;
  text: string;
  score?: number;
}
