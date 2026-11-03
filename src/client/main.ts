import { installTrigger, type ForceRecord } from './trigger.ts';
import { valid, type Pick } from './selection.ts';
const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const popup = $('popover');
const enabled = $<HTMLInputElement>('enabled');
const records: ForceRecord[] = [];
let active: Pick | null = null;
let returnFocus: HTMLElement | null = null;
let opens = 0;
function close() {
  popup.hidden = true; active = null;
  const old = returnFocus; returnFocus = null; old?.focus({ preventScroll: true });
}
function position() {
  if (!active || !valid(active.range)) { close(); return; }
  const r = active.rect;
  popup.style.left = '12px'; popup.style.top = '12px';
  const box = popup.getBoundingClientRect();
  const x = Math.max(12, Math.min(r.left, innerWidth - box.width - 12));
  const y = r.top - box.height - 12 >= 12 ? r.top - box.height - 12 : r.bottom + 12;
  popup.style.left = `${x}px`;
  popup.style.top = `${Math.max(12, Math.min(y, innerHeight - box.height - 12))}px`;
}
const debug = installTrigger(() => enabled.checked, (value, source) => {
  if (!valid(value.range)) return;
  close(); active = value; opens++;
  $('selected-text').textContent = value.text;
  $('trigger-source').textContent = source;
  $('open-count').textContent = String(opens);
  popup.hidden = false; position();
  if (source.startsWith('键盘')) {
    returnFocus = document.activeElement as HTMLElement;
    $('close').focus({ preventScroll: true });
  }
}, record => {
  records.push(record); if (records.length > 300) records.shift();
  $('event-log').textContent = records.slice(-12).map(r => JSON.stringify(r)).join('\n');
  if (record.isTrusted && record.event === 'webkitmouseforcedown' && record.accepted) {
    $('support').textContent = '已收到可信重按 · 系统浮窗是否被抑制仍需人工确认';
  }
});
$('debug').addEventListener('click', debug);
$('close').addEventListener('click', close);
enabled.addEventListener('change', close);
document.addEventListener('keydown', event => { if (event.key === 'Escape') close(); });
document.addEventListener('mousedown', event => { if (!popup.contains(event.target as Node)) close(); }, true);
document.addEventListener('scroll', event => { if (!popup.contains(event.target as Node)) close(); }, true);
document.addEventListener('visibilitychange', () => { if (document.hidden) close(); });
window.addEventListener('resize', close);
new MutationObserver(() => { if (active && !valid(active.range)) close(); }).observe(document.querySelector('main')!, { subtree: true, childList: true, characterData: true });
$('export').addEventListener('click', () => {
  const fields = Object.fromEntries([...document.querySelectorAll<HTMLInputElement | HTMLSelectElement>('[data-record]')].map(el => [el.id, el.value]));
  const report = { stage: 'M0', verdict: 'pending-human-review', date: new Date().toISOString(),
    userAgent: navigator.userAgent, viewport: { width: innerWidth, height: innerHeight, devicePixelRatio },
    fields, popupOpenCount: opens, records };
  const url = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' }));
  const a = document.createElement('a'); a.href = url; a.download = 'transwebquick-m0.json'; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
