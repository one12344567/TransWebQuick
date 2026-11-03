import { pick, selected, type Pick } from './selection.ts';
export type ForceRecord = { event: string; isTrusted: boolean; cancelable: boolean; defaultPrevented: boolean; accepted: boolean; timeMs: number };
export function installTrigger(enabled: () => boolean, show: (pick: Pick, source: string) => void, log: (record: ForceRecord) => void) {
  let recent: Range | null = null;
  let prepared: Pick | null = null;
  let fired = false;
  document.addEventListener('selectionchange', () => { const range = selected(); if (range) recent = range; });
  const record = (event: Event, accepted: boolean) => log({ event: event.type, isTrusted: event.isTrusted,
    cancelable: event.cancelable, defaultPrevented: event.defaultPrevented, accepted, timeMs: Math.round(performance.now()) });
  document.addEventListener('webkitmouseforcewillbegin', event => {
    const mouse = event as MouseEvent;
    prepared = enabled() ? pick(mouse.clientX, mouse.clientY, selected() || recent) : null;
    if (prepared) event.preventDefault();
    record(event, !!prepared);
  }, { passive: false });
  document.addEventListener('webkitmouseforcedown', event => {
    const accepted = enabled() && !!prepared && !fired;
    if (accepted) {
      event.preventDefault(); fired = true;
      show(prepared!, event.isTrusted ? '真实重按事件' : '合成事件 · 不能用于验收');
    }
    record(event, accepted);
  }, { passive: false });
  for (const type of ['webkitmouseforceup', 'mouseup']) document.addEventListener(type, event => {
    record(event, false); prepared = null; fired = false;
  });
  document.addEventListener('keydown', event => {
    if (!event.altKey || event.code !== 'KeyT' || event.ctrlKey || event.metaKey || event.repeat || !enabled()) return;
    if ((event.target as Element)?.closest('input,textarea,select,[contenteditable]')) return;
    const range = selected();
    if (!range) return;
    event.preventDefault();
    show({ range, text: range.toString().trim(), rect: range.getBoundingClientRect() }, '键盘调试 · 不能用于验收');
  });
  return () => {
    const range = selected() || recent;
    if (!range || !enabled()) return;
    show({ range, text: range.toString().trim(), rect: range.getBoundingClientRect() }, '按钮调试 · 不能用于验收');
  };
}
