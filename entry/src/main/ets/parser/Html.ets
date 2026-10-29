import { parseDocument, DomUtils, AnyNode, Element, ParentNode } from '@ohos/htmlparser2';

/** 解析得到的节点（Document / Element / Text / Comment 的联合）。 */
export type HtmlNode = AnyNode;
/**
 * 对 `@ohos/htmlparser2` 的最小封装：
 * 解析 HTML，并提供标签 / `#id` / `.class` 三种基础选择与文本、属性读取。
 */
export class Html {
  static parse(html: string): HtmlNode {
    return parseDocument(html);
  }

  static select(root: HtmlNode, selector: string): HtmlNode[] {
    const scope: ParentNode = root as ParentNode;
    if (selector.startsWith('#')) {
      const id: string = selector.substring(1);
      return DomUtils.findAll((node: AnyNode): boolean => {
        const element: Element | null = Html.asElement(node);
        return element !== null && element.attribs['id'] === id;
      }, scope);
    }
    if (selector.startsWith('.')) {
      const cls: string = selector.substring(1);
      return DomUtils.findAll((node: AnyNode): boolean => {
        const element: Element | null = Html.asElement(node);
        if (element === null) {
          return false;
        }
        const classes: string | undefined = Html.attributeOf(element, 'class');
        return classes !== undefined && classes.split(' ').includes(cls);
      }, scope);
    }
    return DomUtils.getElementsByTagName(selector, root);
  }

  static text(node: HtmlNode): string {
    return DomUtils.textContent(node);
  }

  /** 标签名（小写）；非元素返回空串。 */
  static tagName(node: HtmlNode): string {
    const element: Element | null = Html.asElement(node);
    return element === null ? '' : element.tagName.toLowerCase();
  }

  /** 父节点；无则 `null`。 */
  static parentOf(node: HtmlNode): HtmlNode | null {
    const parent: AnyNode | null = node.parent;
    return parent === null || parent === undefined ? null : parent;
  }

  static attr(node: HtmlNode, name: string): string | null {
    const element: Element | null = Html.asElement(node);
    if (element === null) {
      return null;
    }
    const value: string | undefined = Html.attributeOf(element, name);
    return value === undefined ? null : value;
  }

  private static asElement(node: AnyNode): Element | null {
    return DomUtils.isTag(node) ? node : null;
  }

  private static attributeOf(element: Element, name: string): string | undefined {
    const value: string | undefined = element.attribs[name];
    return value;
  }
}
