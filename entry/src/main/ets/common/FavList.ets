/**
 * 收藏页的纯逻辑（零依赖，单测可直接跑）。
 *
 * 为什么单独放一个文件：`ui/FavoritesPage.ets` 现在 import 了 `@kit.UIDesignKit`（HDS 组件）、
 * `@kit.SensorServiceKit`（振动）等系统 kit，本地单测（`src/test`，非设备用例）跑不动那一整条依赖链——
 * 之前的 `FavoritesBatch.test` 因此卡在「UnitTestArkTS 已结束时执行阶段无输出」。
 * 纯函数留在 `ui/` 里就等于把测试绑死在 UI 栈上。
 */

/** 多选集合切换（已在则去，否则加；返回新数组，调用方整体替换）。 */
export function toggleGid(selected: number[], gid: number): number[] {
  if (selected.indexOf(gid) >= 0) {
    return selected.filter((g: number) => g !== gid);
  }
  return selected.concat([gid]);
}

/**
 * 搜索框提交时该用哪个串。
 *
 * 必须用 `onSubmit` 回调给的 `submitted`，**不能**用输入框里当前的 `draft`：
 * 中文输入法组词期间 `onChange` 已经把拼音写进 `draft` 了（`previewText` 才是"还在组词"的标志），
 * 而 `onSubmit` 的 `submitted` 是提交后的最终串。只读 `draft` 就会拿「cuimian」去搜，
 * 站点 0 条 —— 英文没有组词过程，所以历史表现成"只有中文不生效"。
 * `submitted` 为空时退回 `draft`（部分 ROM 的搜索按钮回调可能不给值）。
 */
export function submittedKeyword(submitted: string, draft: string): string {
  const word: string = submitted.length > 0 ? submitted : draft;
  return word.trim();
}

/** 是否全选（条目非空且选中数相等；`0/0` 不算全选）。 */
export function isAllSelected(selected: number[], total: number): boolean {
  return total > 0 && selected.length === total;
}
