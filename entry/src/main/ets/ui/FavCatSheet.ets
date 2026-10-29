import { HdsListItem } from '@kit.UIDesignKit';

/** 收藏类选项（类号 + 名 + 计数；`count < 0` = 未知，不显示计数）。 */
export interface FavCatOption {
  cat: number;
  name: string;
  count: number;
}

/**
 * 收藏类选择内容（详情收藏 / 收藏页移动共用）。
 * 只出内容，不再自绘遮罩：父组件用官方 `bindSheet` 承载（标题「选择收藏夹」+ 材质在 options 里给）。
 */
@ComponentV2
export struct FavCatSheet {
  @Require @Param options: FavCatOption[];
  @Event onPick: (cat: number) => void = (_cat: number) => {};
  @Event onCancel: () => void = () => {};

  build() {
    List({ space: 8 }) {
      Repeat(this.options)
        .each((ri: RepeatItem<FavCatOption>) => {
          HdsListItem({
            hdsListItemCard: {
              textItem: {
                primaryText: { text: ri.item.name },
                secondaryText: ri.item.count >= 0 ? { text: `${ri.item.count} 项` } : undefined
              },
              onClick: () => {
                this.onPick(ri.item.cat);
              }
            }
          })
        })
        .key((opt: FavCatOption) => `${opt.cat}`)
      // 「取消」放最后一项（`HdsListItem` 自带列表项语义，不再外包 `ListItem`）。
      HdsListItem({
        hdsListItemCard: {
          textItem: { primaryText: { text: '取消' } },
          onClick: () => {
            this.onCancel();
          }
        }
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
}
