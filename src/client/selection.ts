export type Pick = { range: Range; text: string; rect: DOMRect };
const excluded = 'button,input,textarea,select,[contenteditable]:not([contenteditable="false"]),[role="button"],[role="dialog"],nav';
export function region(node: Node | null): Element | null {
  const element = node instanceof Element ? node : node?.parentElement;
  if (!element || element.closest(excluded)) return null;
  return element.closest('[data-query-region]');
}
export function valid(range: Range): boolean {
  return range.startContainer.isConnected && range.endContainer.isConnected &&
    !!region(range.startContainer) && region(range.startContainer) === region(range.endContainer) &&
    range.toString().trim().length > 0 && [...range.toString().trim()].length <= 1000;
}
export function selected(): Range | null {
  const selection = getSelection();
  if (!selection?.rangeCount || selection.isCollapsed) return null;
  const range = selection.getRangeAt(0);
  return valid(range) ? range.cloneRange() : null;
}
export function nearestRect(range: Range, x: number, y: number): DOMRect {
  const rects = [...range.getClientRects()].filter(r => r.width && r.height);
  return rects.sort((a, b) => distance(a, x, y) - distance(b, x, y))[0] || range.getBoundingClientRect();
}
function distance(r: DOMRect, x: number, y: number): number {
  return Math.hypot(Math.max(r.left - x, 0, x - r.right), Math.max(r.top - y, 0, y - r.bottom));
}
export function pick(x: number, y: number, cached: Range | null): Pick | null {
  const hit = document.elementFromPoint(x, y);
  const area = region(hit);
  if (!area) return null;
  if (cached && valid(cached) && region(cached.startContainer) === area) {
    return { range: cached.cloneRange(), text: cached.toString().trim(), rect: nearestRect(cached, x, y) };
  }
  const doc = document as Document & {
    caretPositionFromPoint?: (x: number, y: number) => { offsetNode: Node; offset: number } | null;
    caretRangeFromPoint?: (x: number, y: number) => Range | null;
  };
  const position = doc.caretPositionFromPoint?.(x, y);
  const caret = position ? null : doc.caretRangeFromPoint?.(x, y);
  const node = position?.offsetNode || caret?.startContainer;
  const offset = position?.offset ?? caret?.startOffset;
  if (!(node instanceof Text) || offset === undefined || region(node) !== area) return null;
  const segmenter = new Intl.Segmenter('en', { granularity: 'word' });
  for (const word of segmenter.segment(node.data)) {
    if (!word.isWordLike || offset < word.index || offset > word.index + word.segment.length) continue;
    const range = document.createRange();
    range.setStart(node, word.index);
    range.setEnd(node, word.index + word.segment.length);
    const rect = nearestRect(range, x, y);
    // Caret APIs also snap whitespace to nearby words. Only accept the actual text bounds.
    if (distance(rect, x, y) > 1 || !valid(range)) continue;
    return { range, text: range.toString(), rect };
  }
  return null;
}
