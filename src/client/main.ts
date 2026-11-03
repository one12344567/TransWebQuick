import { renderAnswer } from './answer.ts';
import { extract } from './context.ts';
import { lookup } from './transport.ts';
import type { Lookup } from '../shared/protocol.ts';
import { installTrigger, type ForceRecord } from './trigger.ts';
import { valid, type Pick } from './selection.ts';
const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const popup = $('popover');
const enabled = $<HTMLInputElement>('enabled');
const records: ForceRecord[] = [];
let active: Pick | null = null;
let returnFocus: HTMLElement | null = null;
let opens = 0;
let controller: AbortController | null = null;
let requestId = '';
let snapshot: ReturnType<typeof extract> | null = null;
let mode: Lookup['mode'] = 'brief';
let completedText = '';
const metrics: object[] = [];
const errors: Record<string,string> = {
 CONFIG_MISSING:'请在本机 .env 中配置 DEEPSEEK_API_KEY。',
 UPSTREAM_AUTH:'密钥或账户验证失败，请检查本机配置。',
 UPSTREAM_RATE_LIMIT:'服务暂时限流，请稍后手动重试。',
 UPSTREAM_TIMEOUT:'等待超时，请手动重试。',
 INVALID_OUTPUT:'回答为空或被截断，当前内容未完成。',
 STREAM_INTERRUPTED:'连接中断，当前内容未完成。',
 INVALID_REQUEST:'查询格式无效，请重新选择文本。',
 UPSTREAM_ERROR:'模型服务暂不可用，请稍后手动重试。'
};
async function query(nextMode: Lookup['mode']) {
 if (!active || !valid(active.range) || !snapshot) return;
 controller?.abort(); controller=new AbortController();
 const current=crypto.randomUUID(); requestId=current; mode=nextMode;
 let text=''; completedText='';
 $('answer').textContent=''; $('query-status').textContent='正在结合上下文释义…';
 $<HTMLButtonElement>('detail').disabled=true; $<HTMLButtonElement>('copy').disabled=true; $('retry').hidden=true;
 try {
  await lookup({...snapshot,requestId:current,mode},controller.signal,(event,value)=>{
   if(requestId!==current || popup.hidden) return;
   if(event==='delta') { text+=value.text; renderAnswer($('answer'),text); $('query-status').textContent='正在生成…'; position(); }
   if(event==='done') {
    if(!text.trim()) throw Error('INVALID_OUTPUT');
    renderAnswer($('answer'),text,true);
    completedText=text; $('query-status').textContent=value.cached?'已完成 · 本机缓存':'已完成';
    $<HTMLButtonElement>('detail').disabled=mode==='detail'; $<HTMLButtonElement>('copy').disabled=false;
    metrics.push({requestId:current,mode,...value}); if(metrics.length>200) metrics.shift();
   }
  });
 } catch(error) {
  if(requestId!==current || popup.hidden || controller?.signal.aborted) return;
  const code=error instanceof Error?error.message:'UPSTREAM_ERROR';
  $('query-status').textContent=(text?'未完成 · ':'')+(errors[code] || errors.UPSTREAM_ERROR);
  $('retry').hidden=false;
 }
 position();
}
$('retry').addEventListener('click',()=>query(mode));
$('detail').addEventListener('click',()=>query('detail'));
$('copy').addEventListener('click',async()=>{
 try { await navigator.clipboard.writeText(completedText); $('query-status').textContent='已复制'; }
 catch { $('query-status').textContent='复制失败，请手动选择释义文字。'; }
});
function close() {
  controller?.abort(); requestId=''; snapshot=null;
  popup.hidden = true; active = null;
  const old = returnFocus; returnFocus = null; old?.focus({ preventScroll: true });
}
function position() {
  if (!active || !valid(active.range) || active.range.toString().trim() !== active.text) { close(); return; }
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
  snapshot=extract(value.range);
  $('sources').replaceChildren(...snapshot.sources.map(source=>{
    const item=document.createElement('p'); item.textContent=`${source.id} · ${source.text}`; return item;
  }));
  $('context-note').textContent=snapshot.contextTruncated?'上下文已裁剪':snapshot.contextStatus==='limited'?'上下文有限':'本次查询的原文快照';
  popup.hidden = false; position();
  void query('brief');
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
new MutationObserver(() => { if (active && (!valid(active.range) || active.range.toString().trim() !== active.text)) close(); }).observe(document.querySelector('main')!, { subtree: true, childList: true, characterData: true });
$('export').addEventListener('click', () => {
  const fields = Object.fromEntries([...document.querySelectorAll<HTMLInputElement | HTMLSelectElement>('[data-record]')].map(el => [el.id, el.value]));
  const report = { stage: 'M2', verdict: 'pending-human-review', date: new Date().toISOString(),
    userAgent: navigator.userAgent, viewport: { width: innerWidth, height: innerHeight, devicePixelRatio },
    fields, popupOpenCount: opens, records, metrics };
  const url = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' }));
  const a = document.createElement('a'); a.href = url; a.download = 'transwebquick-m0.json'; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});

$('insert-post').addEventListener('click',()=>{ const p=document.createElement('p'); p.textContent='New update: we plan to ship tomorrow, but the rate limit remains unchanged.'; p.setAttribute('data-query-region',''); $('dynamic-posts').append(p); });
if(new URLSearchParams(location.search).has('debug')) document.body.classList.add('debug-mode');
