import {
  ChipV2, ChipV2Label, ChipV2Options, ChipV2Size, ColorMetrics, SubHeaderV2, SubHeaderV2Title
} from '@kit.ArkUI';
import { Filter } from '../model/Filter';
import { SEARCH_LANGUAGES } from '../search/SearchQuery';
import { CATS, CatItem, SCOPES, ScopeItem, STARS } from '../search/FilterCatalog';
import { CARD_GAP, CARD_RADIUS, PAGE_PADDING } from './Materials';

/** 语言下拉选项（首位 `all` = 不限语言；其余为站点原文，保持全英文避免中英割裂）。 */
const LANG_ANY: string = 'all';
const LANG_OPTIONS: string[] = [LANG_ANY].concat(SEARCH_LANGUAGES);

/** `Select` 的官方选项模型（与 `LANG_OPTIONS` 同序；`Select` 只要 `{ value }`）。 */
function langSelectOptions(): SelectOption[] {
  const out: SelectOption[] = [];
  for (let i = 0; i < LANG_OPTIONS.length; i++) {
    out.push({ value: LANG_OPTIONS[i] });
  }
  return out;
}

/**
 * 搜索页的筛选表单（**内联在页面里**，不是浮层）。
 *
 * 为什么在页面里：空查询时页面上没有别的内容可看，筛选表单本身就是那一屏的内容；
 * 做成抽屉要额外点一次才唤出、还会挡住刚搜出来的结果（真机两轮实测后的结论）。
 * 只在结果页被收起，靠搜索行里的滑块图标展开/收起。
 *
 * 状态纪律：**只读 `@Param`、只发事件**。组件内部不存副本——否则快搜/历史回填
 * （`applyParam`）改了页面状态后，表单还显示旧值。改完不自动搜：唯一生效点仍是
 * 搜索 / 回车（面板盖着结果时即时重搜看不到反馈，只会把每次点击变成一次整页请求）。
 */
@ComponentV2
export struct FilterPanel {
  @Param selectedBits: number[] = [];
  @Param scopes: string[] = [];
  @Param selectedLang: string = '';
  @Param minRating: number = -1;
  @Param langFilter: boolean = false;
  @Param onlyTorrents: boolean = false;
  @Param ignoreFilters: boolean = false;
  @Param pageFromText: string = '';
  @Param pageToText: string = '';
  /** 启用的屏蔽规则（只读展示，点一下 = 本次搜索临时忽略）。 */
  @Param activeRules: Filter[] = [];
  @Param ignoredExclusions: string[] = [];

  @Event onBits: (bits: number[]) => void;
  @Event onScopes: (scopes: string[]) => void;
  @Event onLang: (lang: string) => void;
  @Event onRating: (rating: number) => void;
  @Event onTorrents: (value: boolean) => void;
  @Event onSiteFilters: (value: boolean) => void;
  @Event onPages: (from: string, to: string) => void;
  @Event onIgnored: (ignored: string[]) => void;

  /** 「更多筛选」展开态（低频，默认收起）。纯视图状态，留在这里即可。 */
  @Local moreOpen: boolean = false;

  /** 「更多筛选」里生效了几项：收起时也在行尾提示，避免"改了但看不见"。 */
  @Computed get moreCount(): number {
    let n: number = 0;
    if (this.scopes.length > 0) {
      n += 1;
    }
    if (this.ignoredExclusions.length !== this.activeRules.length) {
      n += 1;
    }
    if (this.onlyTorrents) {
      n += 1;
    }
    if (this.ignoreFilters) {
      n += 1;
    }
    if (this.pageFromText.trim().length > 0 || this.pageToText.trim().length > 0) {
      n += 1;
    }
    return n;
  }

  private toggleBit(bit: number): void {
    const at: number = this.selectedBits.indexOf(bit);
    this.onBits(at >= 0
      ? this.selectedBits.filter((b: number) => b !== bit)
      : this.selectedBits.concat([bit]));
  }

  private toggleScope(key: string): void {
    this.onScopes(this.scopes.indexOf(key) >= 0
      ? this.scopes.filter((k: string) => k !== key)
      : this.scopes.concat([key]));
  }

  /** 排除项唯一键（规则 text 本身就是完整查询词，与 `exclusionQueryOf` 的 ignored 键一致）。 */
  private exclusionKey(rule: Filter): string {
    return rule.text;
  }

  @Builder
  sectionTitle(text: string) {
    SubHeaderV2({
      title: new SubHeaderV2Title({ primaryTitle: text })
    })
  }

  /** 一组 chip 一张卡（底 `bg_secondary`），与页面里的卡片同宽同圆角。 */
  @Builder
  categoriesCard() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Repeat(CATS)
        .each((ri: RepeatItem<CatItem>) => {
          ChipV2({
            chipV2Options: new ChipV2Options({
              label: new ChipV2Label({ text: ri.item.label }),
              size: ChipV2Size.SMALL,
              allowClose: false,
              activated: this.selectedBits.indexOf(ri.item.bit) >= 0,
              onClicked: () => {
                this.toggleBit(ri.item.bit);
              }
            })
          })
            .margin(4)
        })
        .key((cat: CatItem) => cat.label)
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: CARD_GAP })
  }

  @Builder
  languageCard() {
    Row({ space: 8 }) {
      Text('Only show')
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Select(langSelectOptions())
        .selected(this.selectedLang.length > 0 ? SEARCH_LANGUAGES.indexOf(this.selectedLang) + 1 : 0)
        .value(this.selectedLang.length > 0 ? this.selectedLang : LANG_ANY)
        .font({ size: 14 })
        .fontColor($r('sys.color.brand'))
        .backgroundColor(Color.Transparent)
        .onSelect((index: number) => {
          this.onLang(index === 0 ? '' : SEARCH_LANGUAGES[index - 1]);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: CARD_GAP })
  }

  @Builder
  ratingCard() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Repeat(STARS)
        .each((ri: RepeatItem<number>) => {
          ChipV2({
            chipV2Options: new ChipV2Options({
              label: new ChipV2Label({ text: `${ri.item}+` }),
              size: ChipV2Size.SMALL,
              allowClose: false,
              activated: this.minRating === ri.item,
              onClicked: () => {
                this.onRating(this.minRating === ri.item ? -1 : ri.item);
              }
            })
          })
            .margin(4)
        })
        .key((star: number) => `${star}`)
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: CARD_GAP })
  }

  /** 低频分组的总开关：收起时把已生效项数挂在行尾（"改了但看不见"的替代提示）。 */
  @Builder
  moreRow() {
    Row({ space: 6 }) {
      Text('更多筛选')
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
      if (this.moreCount > 0) {
        Text(`${this.moreCount} 项`)
          .fontSize(12)
          .fontColor($r('sys.color.brand'))
      }
      Blank()
      SymbolGlyph($r(this.moreOpen ? 'sys.symbol.chevron_up' : 'sys.symbol.chevron_down'))
        .fontSize(18)
        .fontColor([$r('app.color.text_secondary')])
        .padding(12)
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: CARD_GAP })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      // 展开后的分组紧跟在折叠行下方：它在滚动内容里，几行之后就落在视口内，不需要额外滚动。
      this.moreOpen = !this.moreOpen;
    })
  }

  @Builder
  scopeCard() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Repeat(SCOPES)
        .each((ri: RepeatItem<ScopeItem>) => {
          ChipV2({
            chipV2Options: new ChipV2Options({
              label: new ChipV2Label({ text: ri.item.label }),
              size: ChipV2Size.SMALL,
              allowClose: false,
              activated: this.scopes.indexOf(ri.item.key) >= 0,
              onClicked: () => {
                this.toggleScope(ri.item.key);
              }
            })
          })
            .margin(4)
        })
        .key((scope: ScopeItem) => scope.key)
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: CARD_GAP })
  }

  /**
   * 屏蔽规则：**不是**可选偏好，而是全局规则在本次搜索里的临时豁免，所以单独一段并带说明。
   * 没有启用的规则时整组不渲染（否则会出现一个空标题）。
   */
  @Builder
  exclusionsSection() {
    this.sectionTitle('Exclusions')
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Repeat(this.activeRules)
        .each((ri: RepeatItem<Filter>) => {
          ChipV2({
            chipV2Options: new ChipV2Options({
              label: new ChipV2Label({
                text: ri.item.text,
                activatedFontColor: ColorMetrics.resourceColor($r('app.color.danger'))
              }),
              size: ChipV2Size.SMALL,
              allowClose: false,
              // 未忽略 = 生效排除（danger 色调）；忽略 = 普通芯片。
              activated: this.ignoredExclusions.indexOf(this.exclusionKey(ri.item)) < 0,
              activatedBackgroundColor: ColorMetrics.resourceColor($r('app.color.chip_danger_bg')),
              onClicked: () => {
                const key: string = this.exclusionKey(ri.item);
                this.onIgnored(this.ignoredExclusions.indexOf(key) >= 0
                  ? this.ignoredExclusions.filter((k: string) => k !== key)
                  : this.ignoredExclusions.concat([key]));
              }
            })
          })
            .margin(4)
        })
        .key((rule: Filter) => `${rule.id}`)
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    Text('点一下可临时忽略这条规则（只影响本次搜索）')
      .fontSize(11)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .margin({ bottom: CARD_GAP })
  }

  /** 官方高级搜索参数（`f_sto` / `f_sfl,f_sfu,f_sft` / 页数区间）。 */
  @Builder
  advancedCard() {
    Column({ space: 8 }) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        ChipV2({
          chipV2Options: new ChipV2Options({
            label: new ChipV2Label({ text: '有种子' }),
            size: ChipV2Size.SMALL,
            allowClose: false,
            activated: this.onlyTorrents,
            onClicked: () => {
              this.onTorrents(!this.onlyTorrents);
            }
          })
        })
          .margin(4)
        ChipV2({
          chipV2Options: new ChipV2Options({
            label: new ChipV2Label({ text: '忽略站点过滤' }),
            size: ChipV2Size.SMALL,
            allowClose: false,
            activated: this.ignoreFilters,
            onClicked: () => {
              this.onSiteFilters(!this.ignoreFilters);
            }
          })
        })
          .margin(4)
      }
      .width('100%')
      Row({ space: 8 }) {
        Text('页数')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        TextInput({ text: this.pageFromText, placeholder: '从' })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(36)
          .onChange((value: string) => {
            this.onPages(value, this.pageToText);
          })
        Text('–')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        TextInput({ text: this.pageToText, placeholder: '到' })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(36)
          .onChange((value: string) => {
            this.onPages(this.pageFromText, value);
          })
      }
      .width('100%')
      Text('页数区间过窄（如 1000 到 10）会返回 0 条；留空 = 不限。')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: CARD_GAP })
  }

  build() {
    Column() {
      this.sectionTitle('Categories')
      this.categoriesCard()

      this.sectionTitle('Language')
      this.languageCard()

      this.sectionTitle('Minimum Rating')
      this.ratingCard()

      this.moreRow()
      if (this.moreOpen) {
        this.sectionTitle('Search Scope')
        this.scopeCard()
        if (this.activeRules.length > 0) {
          this.exclusionsSection()
        }
        this.sectionTitle('Advanced')
        this.advancedCard()
      }
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
  }
}
