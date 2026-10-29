import { image } from '@kit.ImageKit';
import { Logger } from '../common/Logger';
import { PreviewCell } from '../model/PreviewCell';
import { PreviewSpriteCache } from '../service/PreviewSpriteCache';
import { PreviewCropCell } from './PreviewCropCell';

/** 邻域窗口半宽（页）：滑杆停在某页后，看它前后各 10 页的缩略图。 */
const WINDOW_SPAN: number = 10;
/** 条带缩略图高度（vp）：固定等高，不同裁剪比例的图按 cover 对齐。 */
const STRIP_CELL_H: number = 110;
/** 条带占位高度（vp）：载入中/失败时保留同样高度，按钮不跳位。 */
const STRIP_H: number = 140;

/**
 * 跳页半模态：**数字定位 + 邻域缩略图确认**。
 *
 * 为什么不用缩略图做全量定位器：预览图按 20 页一块从站点取（块号 = 页 / 20），
 * 2000 页的画廊要显示全部缩略图 = 100 个请求；这里只在用户停下的位置取 1–2 块。
 *
 * 状态（页码 / 窗口 / 加载态）全在本组件内：`bindSheet` 的 builder 只在打开时构建一次，
 * 打开后再改父组件状态不会重绘，所以数据由子组件自己拉。
 */
@ComponentV2
export struct JumpSheet {
  @Param pages: number = 0;
  /** 打开时停在哪一页（0 起；通常 = 当前阅读进度）。 */
  @Param initialPage: number = 0;
  /** 取某页前后 `span` 页的预览格（父组件注入：走站点分块接口 + 缓存）。 */
  @Require @Param fetchWindow: (page: number, span: number) => Promise<PreviewCell[]>;
  /** 取格子成品缩略图（父组件注入：走 `PreviewSpriteCache`）。 */
  @Require @Param spriteOf: (cell: PreviewCell) => Promise<image.PixelMap | null>;
  @Event onPick: (page: number) => void = (_page: number) => {};

  /** 目标页（0 起）。 */
  @Local page: number = 0;
  /** 输入框文本（允许中途是非法/超范围值，提交时才收敛）。 */
  @Local pageText: string = '1';
  @Local cells: PreviewCell[] = [];
  @Local windowBusy: boolean = false;
  @Local windowMessage: string = '';
  /** 窗口代际：连续拖动 / 组件销毁后丢弃旧响应。 */
  private gen: number = 0;
  private stripScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.page = this.clamp(this.initialPage);
    this.pageText = `${this.page + 1}`;
    this.reloadWindow();
  }

  /** 销毁后让在飞的取块结果作废（否则回写已销毁组件的 @Local，并多持有实例一会儿）。 */
  aboutToDisAppear(): void {
    this.gen += 1;
  }

  private clamp(page: number): number {
    if (this.pages <= 0) {
      return 0;
    }
    if (page < 0) {
      return 0;
    }
    return page > this.pages - 1 ? this.pages - 1 : page;
  }

  /** 定页：页码、输入框、附近缩略图一起跟上（滑杆松手 / 输入框提交共用）。 */
  private applyPage(page: number): void {
    this.page = this.clamp(page);
    this.pageText = `${this.page + 1}`;
    this.reloadWindow();
  }

  /** 输入框收敛：非数字或超范围不报错，回到上一次的有效页。 */
  private commitText(): void {
    const parsed: number = Number.parseInt(this.pageText, 10);
    this.applyPage(Number.isNaN(parsed) ? this.page : parsed - 1);
  }

  /** 当前页在条带里的下标（窗口按页升序，正常情况下正好在正中）。 */
  private centerIndex(): number {
    if (this.cells.length === 0) {
      return 0;
    }
    const index: number = this.page - this.cells[0].page;
    if (index < 0) {
      return 0;
    }
    return index > this.cells.length - 1 ? this.cells.length - 1 : index;
  }

  /** 把当前页滚到条带中间：`List` 的 `initialIndex` 只在创建时生效，换窗口要显式滚。 */
  private centerStrip(): void {
    // 数据刚换、列表还没重新布局，等一帧再滚；这里不碰 UIContext，脱离 UI 上下文调它有风险。
    setTimeout(() => {
      this.stripScroller.scrollToIndex(this.centerIndex(), false, ScrollAlign.CENTER);
    }, 0);
  }

  private reloadWindow(): void {
    const g: number = ++this.gen;
    // 捕获本次请求的页：拖动中 `this.page` 会变，回调里不能再读它（否则 from/to 与实际窗口不符）。
    const targetPage: number = this.page;
    this.windowBusy = true;
    this.windowMessage = '';
    // 清掉旧窗口：否则新窗口到达前条带还在展示上一页的画面，失败时更会一直停在旧图上。
    this.cells = [];
    this.fetchWindow(targetPage, WINDOW_SPAN).then((cells: PreviewCell[]) => {
      if (g !== this.gen) {
        return;
      }
      this.windowBusy = false;
      this.cells = cells;
      const from: number = Math.max(0, targetPage - WINDOW_SPAN);
      const to: number = Math.min(this.pages - 1, targetPage + WINDOW_SPAN);
      if (cells.length === 0) {
        this.windowMessage = '这一页附近没有预览图';
        return;
      }
      if (cells.length < to - from + 1) {
        this.windowMessage = '部分预览未取到';
      }
      this.centerStrip();
    }).catch((e: object) => {
      if (g !== this.gen) {
        return;
      }
      this.windowBusy = false;
      this.windowMessage = '附近预览加载失败';
      Logger.error('Detail', `jump window failed page=${targetPage}: ${e}`);
    });
  }

  @Builder
  pageInput() {
    Row({ space: 8 }) {
      Text('第')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      TextInput({ text: this.pageText })
        .type(InputType.Number)
        .width(96)
        .height(44)
        .textAlign(TextAlign.Center)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .borderRadius(12)
        .backgroundColor($r('app.color.bg_secondary'))
        .onChange((value: string) => {
          this.pageText = value;
        })
        .onSubmit(() => {
          this.commitText();
        })
        .onBlur(() => {
          this.commitText();
        })
      Text(`/ ${this.pages} 页`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: 12 }) {
      this.pageInput()
      Slider({ value: this.page, min: 0, max: Math.max(this.pages - 1, 0), step: 1 })
        .width('100%')
        .onChange((value: number, mode: SliderChangeMode) => {
          const v: number = Math.round(value);
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            // 拖动中只跟数字（不联网），松手才取这一片缩略图。
            this.page = v;
            this.pageText = `${v + 1}`;
            return;
          }
          this.applyPage(v);
        })
      // 载入/失败提示：固定占一行高度，条带区高度不变，主按钮不跳位。
      Text(this.windowBusy ? '载入附近预览…' : this.windowMessage)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .height(16)
      // 附近缩略图：横向一条，滑一滑就能看这一页前后大概是什么内容；点任意一张 = 从这一页开始读。
      if (this.cells.length > 0) {
        List({ space: 8, scroller: this.stripScroller, initialIndex: this.centerIndex() }) {
          Repeat(this.cells)
            .each((ri: RepeatItem<PreviewCell>) => {
              ListItem() {
                PreviewCropCell({
                  page: ri.item.page,
                  w: ri.item.w,
                  h: ri.item.h,
                  cacheKey: PreviewSpriteCache.keyOf(ri.item.url, ri.item.x, ri.item.y, ri.item.w, ri.item.h),
                  fixedH: STRIP_CELL_H,
                  load: () => this.spriteOf(ri.item)
                })
                  .width(78)
              }
              .onClick(() => {
                this.onPick(ri.item.page);
              })
              // 当前页那一格固定 id：真机脚本靠它复现「点缩略图开始读」，不用猜页码。
              .id(ri.item.page === this.page ? 'jump-page-current' : `jump-page-${ri.item.page}`)
            })
            .key((cell: PreviewCell) => `${cell.page}`)
        }
        .listDirection(Axis.Horizontal)
        .width('100%')
        .height(STRIP_H)
        .scrollBar(BarState.Off)
        .onAppear(() => {
          // 列表每次换窗口都会重建（cells 先清空再填），这里挂居中比依赖 initialIndex 稳。
          this.centerStrip();
        })
      } else {
        Row()
          .width('100%')
          .height(STRIP_H)
      }
      // 点缩略图就是从那一页开始读，所以常态下不需要底部按钮；
      // 只在缩略图没取到（这一片全失败 / 没有预览）时留一个兜底，否则输好页码却没东西可点。
      if (this.cells.length === 0 && !this.windowBusy) {
        Button(`去第 ${this.page + 1} 页`)
          .width('100%')
          .height(44)
          .onClick(() => {
            this.onPick(this.page);
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }
}
