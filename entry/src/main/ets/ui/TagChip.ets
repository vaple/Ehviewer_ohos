import { ChipV2, ChipV2Label, ChipV2Options, ChipV2Size, LengthMetrics } from '@kit.ArkUI';
import { hapticTap } from '../common/Haptic';
import { TagDb } from '../tagdb/TagDb';

/**
 * 标签 chip 与命名空间前缀（详情页标签卡用）。
 *
 * 为什么译文在组件自己的 `build` 里查、而不是由页面当 `@Param` 传进来：
 * 译文依赖模块级 `tagDbRev.rev`（快照加载完成 / 开关切换时自增）。若页面读 `rev`，整页（含预览图 `Repeat`）
 * 都会重建；读在 chip 内部，重绘范围就只有这些 chip 和命名空间前缀。
 * 四个动作回调仍然传**原串** `ns`/`tag`：翻译只影响显示，搜索 / 复制 / 屏蔽的行为与原来完全一致。
 *
 * 点按 = 搜索；长按菜单 = 搜索 / 两种排除 / 查看释义（仅在有释义时出现）/ 复制。
 */
@ComponentV2
export struct TagChip {
  @Require @Param ns: string;
  @Require @Param tag: string;
  @Event onSearch: (ns: string, tag: string) => void = (_ns: string, _tag: string) => {};
  @Event onBlock: (ns: string, tag: string) => void = (_ns: string, _tag: string) => {};
  @Event onExcludeSearch: (ns: string, tag: string) => void = (_ns: string, _tag: string) => {};
  @Event onCopy: (ns: string, tag: string) => void = (_ns: string, _tag: string) => {};
  @Event onExplain: (ns: string, tag: string) => void = (_ns: string, _tag: string) => {};

  @Builder
  tagMenu() {
    Menu() {
      MenuItem({ content: '搜索' })
        .onClick(() => {
          this.onSearch(this.ns, this.tag);
        })
      MenuItem({ content: '从本次搜索排除' })
        .onClick(() => {
          this.onExcludeSearch(this.ns, this.tag);
        })
      MenuItem({ content: '加入搜索排除' })
        .onClick(() => {
          this.onBlock(this.ns, this.tag);
        })
      // 约 3/4 的 tag 没有释义：没有就整项不渲染，不拿「暂无释义」占位。
      if (TagDb.intro(this.ns, this.tag).length > 0) {
        MenuItem({ content: '查看释义' })
          .onClick(() => {
            this.onExplain(this.ns, this.tag);
          })
      }
      MenuItem({ content: '复制标签内容' })
        .onClick(() => {
          this.onCopy(this.ns, this.tag);
        })
    }
  }

  build() {
    // 译文必须在这里查（不能声明局部变量——`build` 只能有 UI 描述）：
    // `translateTag` 首行读 `tagDbRev.rev`，UI 执行期间读到就建立依赖 → 快照到位后只有 chip 重画。
    // 未命中回退原文（`translateTag` 的语义），不显示占位符。
    // 官方 ChipV2（应用级材质开启后自带系统样式）；长按菜单挂在外层 Row（自定义组件的属性链挂不了通用属性）。
    Row() {
      ChipV2({
        chipV2Options: new ChipV2Options({
          label: new ChipV2Label({ text: TagDb.translateTag(this.ns, this.tag), fontSize: LengthMetrics.fp(12) }),
          size: ChipV2Size.SMALL,
          allowClose: false,
          onClicked: () => {
            this.onSearch(this.ns, this.tag);
          }
        })
      })
    }
    .margin(4)
    // `onAppear` = 菜单真正弹出来那一刻 → 轻振一次（长按被识别的确认，与菜单动画同步；点按不受影响）。
    .bindContextMenu(this.tagMenu, ResponseType.LongPress, { onAppear: () => hapticTap() })
  }
}

/** 标签卡里的命名空间前缀（`女性:` / `原作:`）；未命中回退英文原名。 */
@ComponentV2
export struct NsLabel {
  @Require @Param ns: string;

  build() {
    // 与 `TagChip` 同理：在自身 build 里读 `TagDb`，只当前缀重绘，不牵动页面的预览图 `Repeat`。
    Text(`${TagDb.translateNs(this.ns)}:`)
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))
      .margin(4)
      .padding({ top: 4, bottom: 4 })
  }
}
