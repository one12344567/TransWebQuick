import { chars, type Source, type Lookup } from '../shared/protocol.ts';
import { valid } from './selection.ts';
function visibleText(el: Element): string { return (el as HTMLElement).innerText?.trim() || ''; }
export function extract(range: Range): Omit<Lookup,'requestId'|'mode'> {
  if (!valid(range)) throw Error('INVALID_SELECTION');
  const text=range.toString().trim();
  const node=range.startContainer instanceof Element ? range.startContainer : range.startContainer.parentElement!;
  const block=node.closest('td,th,li,p,blockquote,h1,h2,h3') || node.closest('article');
  const sources:Source[]=[]; let remaining=5000, truncated=false;
  function add(kind:Source['kind'], text:string) {
    text=text.trim(); if (!text || sources.some(s=>s.text===text)) return;
    if (sources.length>=6 || remaining===0) { truncated=true; return; }
    if (chars(text)>remaining) { text=[...text].slice(0,remaining).join(''); truncated=true; }
    sources.push({id:`s${sources.length+1}`,kind,text}); remaining-=chars(text);
  }
  const local=block ? visibleText(block) : text;
  // Always retain selected text, even when a long source needs a centered excerpt.
  const at=local.indexOf(text);
  let excerpt=local;
  if (chars(local)>3000 && at>=0) {
    excerpt=[...local.slice(0,at)].slice(-600).join('')+text+[...local.slice(at+text.length)].slice(0,1000).join(''); truncated=true;
  }
  if (!excerpt.includes(text)) add('sentence',text);
  const cell=node.closest('td,th') as HTMLTableCellElement|null;
  if (cell) {
    add('table',visibleText(cell));
    const row=cell.parentElement;
    const rowHead=row?.querySelector('th[scope="row"]'); if (rowHead && rowHead!==cell) add('heading',visibleText(rowHead));
    const table=cell.closest('table');
    const col=table?.querySelector('thead tr')?.children[cell.cellIndex]; if(col) add('heading',visibleText(col));
  } else {
    add(block?.matches('li')?'list-item':block?.matches('blockquote')?'quote':'paragraph',excerpt);
    const area=node.closest('article,section,[data-query-region]');
    const heading=area?.querySelector('h1,h2,h3'); if(heading && heading!==block) add('heading',visibleText(heading));
    const quote=node.closest('blockquote');
    const parent=quote?.parentElement?.closest('article');
    const parentText=parent?.querySelector(':scope > p'); if(parentText) add('parent-post',visibleText(parentText));
  }
  return {selectedText:text,language:'zh-CN',contextVersion:'extract-v1',contextStatus:block?'complete':'limited',contextTruncated:truncated,sources};
}
