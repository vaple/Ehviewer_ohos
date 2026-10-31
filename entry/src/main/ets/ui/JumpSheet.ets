import { image } from '@kit.ImageKit';
import { Logger } from '../common/Logger';
import {
  centerSideOffset, chunksInRange, prefetchChunks,
  JUMP_STRIP_CELL_W, JUMP_STRIP_EDGE_CELLS, JUMP_STRIP_GAP
} from '../common/JumpStrip';
import { PreviewCell } from '../model/PreviewCell';
import { JumpStripCell } from './JumpStripCell';
import { PreviewStripSource } from './PreviewStripSource';

/** 条带缩略图高度（vp）：固定等高，不同裁剪比例的图按 cover 对齐。 */
const STRIP_CELL_H: number = 110;
/** 条带区高度（vp）：载入中/失败时保留同样高度，提示行与滑杆不跳位。 */
const STRIP_H: number = 140;
/** 停稳后的静默窗（ms）：吸附动画收尾仍可能有零散回调，等它安静再取块。 */
const SETTLE_MS: number = 120;

/**
 * 跳页半模态：**数字定位 + 连续缩略图条带**。
 *
 * 条带覆盖 0..pages-1（每页一格，`LazyForEach` 只建可视的十来个），正中格驱动页码与滑杆；
 * 点任意一格 = 从那一页开始读（方案 A：滑=选，点=去）。
 *
 * 取块纪律（用户重点要求）：**甩动中不发请求**。唯一入口是 `settleNow()`，而它只由
 * `onScrollStart` 之后取消、`onScrollStop` 之后 120ms 触发（外加打开时一次）。程序化滚动
 * （滑杆/输入框）不在动画中途取块——那时的可视窗还是中途位置，取了就是浪费。
 *
 * 状态全在本组件内：`bindSheet` 的 builder 只在打开时构建一次，打开后再改父组件状态不会重绘（`ui/AGENTS.md` #20）。
 */
@ComponentV2
export struct JumpSheet {
  @Param pages: number = 0;
  /** 打开时停在哪一页（0 起；通常 = 当前阅读进度）。 */
  @Param initialPage: number = 0;
  /** 取某一块（20 页）的预览格（父组件注入：与详情网格共用缓存）。 */
  @Require @Param loadChunk: (chunk: number) => Promise<PreviewCell[]>;
  /** 取格子成品缩略图（父组件注入：走 `PreviewSpriteCache`）。 */
  @Require @Param spriteOf: (cell: PreviewCell) => Promise<image.PixelMap | null>;
  @Event onPick: (page: number) => void = (_page: number) => {};

  /** 目标页（0 起）。 */
  @Local page: number = 0;
  /** 输入框文本（允许中途是非法/超范围值，提交时才收敛）。 */
  @Local pageText: string = '1';
  /** 提示行：有块在飞 → 载入中；仍有失败块 → 一句人话；否则空。 */
  @Local hint: string = '';
  @Local busy: number = 0;
  /** 条带视口宽度（vp，`onAreaChange` 读；首尾居中 offset 要用）。 */
  @Local stripW: number = 0;

  private source: PreviewStripSource = new PreviewStripSource(0);
  private stripScroller: Scroller = new Scroller();
  /** 可视窗页范围（`onScrollIndex` 报的 start/end；停稳取块就用它）。 */
  private visibleStart: number = -1;
  private visibleEnd: number = -1;
  private inflight: Set<number> = new Set<number>();
  private doneChunks: Set<number> = new Set<number>();
  private failedChunks: Set<number> = new Set<number>();
  private settleTimer: number = -1;
  /** 程序化滚动的兜底定时器（只恢复状态；非动画跳转才补一次 settle）。 */
  private scrollTimer: number = -1;
  /** 组件已销毁：所有在飞响应、定时回调一律作废（否则会给已关闭的半模态发请求）。 */
  private gone: boolean = false;
  /** 输入框聚焦中：滚动不覆盖用户正在输入的文字。 */
  private editing: boolean = false;
  private scrolling: boolean = false;
  /** 首次布局完成前忽略 `onScrollIndex`（它会先报初始中心 0）。 */
  private ready: boolean = false;
  /** 程序化滚动（滑杆/输入框/首屏定位）期间，`onScrollIndex` 不代表用户选择。 */
  private programmatic: boolean = false;
  private initialScrolled: boolean = false;

  aboutToAppear(): void {
    this.page = this.clamp(this.initialPage);
    this.pageText = `${this.page + 1}`;
    this.source = new PreviewStripSource(this.pages);
    // 首屏不能先给一片灰：打开就取中心块，不等防抖。
    this.visibleStart = this.page;
    this.visibleEnd = this.page;
    this.settleNow();
  }

  /** 销毁后让在飞的取块结果与定时器全部作废。 */
  aboutToDisAppear(): void {
    this.gone = true;
    this.cancelSettle();
    this.cancelScrollTimer();
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

  private cancelSettle(): void {
    if (this.settleTimer >= 0) {
      clearTimeout(this.settleTimer);
      this.settleTimer = -1;
    }
  }

  private cancelScrollTimer(): void {
    if (this.scrollTimer >= 0) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }

  /** 停稳后再取块：吸附结束仍可能有零散回调，留一个短静默窗。 */
  private scheduleSettle(): void {
    this.cancelSettle();
    this.settleTimer = setTimeout(() => {
      this.settleTimer = -1;
      this.settleNow();
    }, SETTLE_MS);
  }

  /** 一次性把「可视窗覆盖的块 + 贴近边界时相邻块」发出去（已在飞/已取到的不重发）。 */
  private settleNow(): void {
    if (this.gone || this.pages <= 0 || this.scrolling) {
      return;
    }
    const start: number = this.visibleStart >= 0 ? this.visibleStart : this.page;
    const end: number = this.visibleEnd >= 0 ? this.visibleEnd : this.page;
    const wanted: number[] = chunksInRange(start, end, this.pages)
      .concat(prefetchChunks(start, end, this.pages, JUMP_STRIP_EDGE_CELLS));
    const seen: Set<number> = new Set<number>();
    let anyFailedVisible: boolean = false;
    for (let i = 0; i < wanted.length; i++) {
      const chunk: number = wanted[i];
      if (this.failedChunks.has(chunk)) {
        anyFailedVisible = true;
      }
      if (seen.has(chunk)) {
        continue;
      }
      seen.add(chunk);
      this.ensureChunk(chunk);
    }
    // 失败提示只针对「当前可视窗」：滑走的失败块不再挂着一条永远不消失的提示。
    if (!anyFailedVisible) {
      this.hint = '';
    }
  }

  private ensureChunk(chunk: number): void {
    if (this.gone || this.inflight.has(chunk) || this.doneChunks.has(chunk)) {
      return;
    }
    this.inflight.add(chunk);
    this.busy += 1;
    this.loadChunk(chunk).then((cells: PreviewCell[]) => {
      if (this.gone) {
        return;
      }
      this.inflight.delete(chunk);
      this.failedChunks.delete(chunk);
      // 空数组 = 这块确实没有预览（请求本身成功），才记 done；请求失败不记，下次 settle 可重试。
      this.doneChunks.add(chunk);
      this.busy -= 1;
      if (this.failedChunks.size === 0) {
        this.hint = '';
      }
      for (let i = 0; i < cells.length; i++) {
        this.source.setCell(cells[i]);
      }
    }).catch((e: object) => {
      if (this.gone) {
        return;
      }
      this.inflight.delete(chunk);
      this.failedChunks.add(chunk);
      this.busy -= 1;
      this.hint = '这一段预览没取到';
      Logger.error('Detail', `jump strip chunk failed chunk=${chunk}: ${e}`);
    });
  }

  /**
   * 程序化滚动：这段时间的 `onScrollIndex` 不代表用户选择。
   *
   * `settleWhenIdle` 决定兜底要不要补 settle：拖动滑杆传 `false`（拖动中绝不取块），
   * 首屏定位 / 无动画跳转传 `true`（这类跳转没有动画，不保证触发 `onScrollStop`）。
   * 动画路径永远不在这里 settle——真实取块只由 `onScrollStop` 负责。
   */
  private scrollToPage(page: number, animated: boolean, settleWhenIdle: boolean): void {
    if (this.gone) {
      return;
    }
    this.programmatic = true;
    this.stripScroller.scrollToIndex(page, animated, ScrollAlign.CENTER);
    // 兜底只恢复状态；动画给足余量（个别版本对程序化滚动不发 onScrollStop）。
    this.cancelScrollTimer();
    this.scrollTimer = setTimeout(() => {
      this.scrollTimer = -1;
      if (this.gone || !this.programmatic) {
        return;
      }
      this.programmatic = false;
      this.scrolling = false;
      if (!animated && settleWhenIdle) {
        this.scheduleSettle();
      }
    }, animated ? 1500 : 120);
  }

  private onCenter(center: number, start: number, end: number): void {
    this.visibleStart = start;
    this.visibleEnd = end;
    if (!this.ready || this.programmatic || center < 0) {
      return;
    }
    const next: number = this.clamp(center);
    if (next === this.page) {
      return;
    }
    this.page = next;
    if (!this.editing) {
      this.pageText = `${next + 1}`;
    }
  }

  /** 把页写进状态并滚过去；真实取块由 `onScrollStop` 或「已经在目标位」的直接 settle 负责。 */
  private applyPage(page: number, animated: boolean): void {
    const target: number = this.clamp(page);
    // 滑杆拖动中已经把条带挪到目标页了：松手不会再产生动画，`onScrollStop` 不会来，
    // 必须在这里直接 settle（否则这一页的缩略图永远不取）。
    const moved: boolean = target !== this.page;
    this.page = target;
    if (!this.editing) {
      this.pageText = `${this.page + 1}`;
    }
    this.scrollToPage(this.page, animated, true);
    if (!moved) {
      this.scheduleSettle();
    }
  }

  /** 输入框收敛：非数字或超范围不报错，回到上一次的有效页。 */
  private commitText(): void {
    const parsed: number = Number.parseInt(this.pageText, 10);
    this.applyPage(Number.isNaN(parsed) ? this.page : parsed - 1, true);
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
        .onFocus(() => {
          this.editing = true;
        })
        .onSubmit(() => {
          this.commitText();
        })
        .onBlur(() => {
          this.editing = false;
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
            // 拖动中只跟手，绝不取块（settleWhenIdle=false → 兜底定时器也只恢复状态）。
            this.page = v;
            if (!this.editing) {
              this.pageText = `${v + 1}`;
            }
            this.scrollToPage(v, false, false);
            this.cancelSettle();
            return;
          }
          this.applyPage(v, true);
        })
      // 载入/失败提示：固定一行高度，条带区高度不变，滑杆不跳位。
      Text(this.busy > 0 ? '载入预览…' : this.hint)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .height(16)
      // 全画廊连续条带：每页一格，正中格 = 当前页；点任意一格从那一页开始读。
      List({ space: JUMP_STRIP_GAP, scroller: this.stripScroller }) {
        LazyForEach(this.source, (cell: PreviewCell) => {
          ListItem() {
            JumpStripCell({
              cell: cell,
              cellW: JUMP_STRIP_CELL_W,
              cellH: STRIP_CELL_H,
              spriteOf: this.spriteOf
            })
          }
          .width(JUMP_STRIP_CELL_W)
          .id(`jump-page-${cell.page}`)
          .onClick(() => {
            this.onPick(cell.page);
          })
        }, (cell: PreviewCell) => `${cell.page}`)
      }
      .listDirection(Axis.Horizontal)
      .width('100%')
      .height(STRIP_H)
      .scrollBar(BarState.Off)
      .cachedCount(2)
      .scrollSnapAlign(ScrollSnapAlign.CENTER)
      .contentStartOffset(centerSideOffset(this.stripW, JUMP_STRIP_CELL_W))
      .contentEndOffset(centerSideOffset(this.stripW, JUMP_STRIP_CELL_W))
      .onTouch((event: TouchEvent) => {
        // 手指按下 = 用户接管：立刻解除程序化滚动的屏蔽，不能让「滑=选」被吞掉。
        if (event.type === TouchType.Down) {
          this.programmatic = false;
          this.cancelScrollTimer();
        }
      })
      .onAreaChange((_old: Area, now: Area) => {
        const w: number = Number(now.width);
        if (w === this.stripW) {
          return;
        }
        this.stripW = w;
        if (this.pages <= 0 || w <= 0) {
          return;
        }
        const first: boolean = !this.initialScrolled;
        this.initialScrolled = true;
        // offset 要等这一帧重新布局才生效，下一拍再定位；ready 也必须在这拍才置真，
        // 否则这段时间的 onScrollIndex 会把目标页改回 1、随后滚到错误的页。
        // 首次之后的宽度变化（折叠/旋转）= offset 变了，也要重新居中。
        setTimeout(() => {
          if (first) {
            this.ready = true;
            this.scrollToPage(this.page, false, true);
          } else {
            this.scrollToPage(this.page, false, false);
          }
        }, 32);
      })
      .onScrollIndex((start: number, end: number, center: number) => {
        this.onCenter(center, start, end);
      })
      .onScrollStart(() => {
        this.scrolling = true;
        this.cancelSettle();
        // 用户接管：程序化滚动的兜底定时器不能再清 `scrolling`。
        this.cancelScrollTimer();
      })
      .onScrollStop(() => {
        this.cancelScrollTimer();
        this.scrolling = false;
        this.programmatic = false;
        this.scheduleSettle();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }
}
