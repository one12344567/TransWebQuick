export type Source = { id: string; kind: 'sentence'|'paragraph'|'list-item'|'heading'|'table'|'quote'|'parent-post'; text: string };
export type Lookup = { requestId: string; mode: 'brief'|'detail'; selectedText: string; language: 'zh-CN'; contextVersion: string; contextStatus: 'complete'|'limited'; contextTruncated: boolean; sources: Source[] };
export const chars = (text: string) => [...text].length;
export function validate(input: unknown): Lookup {
  const v = input as Lookup;
  const string = (s: unknown, max: number) => typeof s === 'string' && s.trim().length > 0 && chars(s) <= max;
  if (!v || !string(v.requestId, 64) || !['brief','detail'].includes(v.mode) || !string(v.selectedText,1000) || v.language !== 'zh-CN' || !string(v.contextVersion,64) || !['complete','limited'].includes(v.contextStatus) || typeof v.contextTruncated !== 'boolean' || !Array.isArray(v.sources) || v.sources.length < 1 || v.sources.length > 6) throw Error('INVALID_REQUEST');
  const kinds = ['sentence','paragraph','list-item','heading','table','quote','parent-post'];
  if (v.sources.some(s => !s || !string(s.id,64) || !kinds.includes(s.kind) || !string(s.text,5000)) || new Set(v.sources.map(s=>s.id)).size !== v.sources.length || v.sources.reduce((n,s)=>n+chars(s.text),0)>5000) throw Error('INVALID_REQUEST');
  return { requestId:v.requestId, mode:v.mode, selectedText:v.selectedText, language:v.language, contextVersion:v.contextVersion, contextStatus:v.contextStatus, contextTruncated:v.contextTruncated, sources:v.sources.map(({id,kind,text})=>({id,kind,text})) };
}
// A line parser shared by upstream and browser; streaming TextDecoder preserves split UTF-8.
export async function* events(stream: ReadableStream<Uint8Array>) {
  const reader = stream.getReader(); const decoder = new TextDecoder();
  let buffer = '', event = 'message', data: string[] = [];
  try {
    while (true) {
      const part = await reader.read();
      buffer += decoder.decode(part.value, { stream: !part.done });
      let index: number;
      while ((index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0,index).replace(/\r$/, ''); buffer = buffer.slice(index+1);
        if (!line) {
          if (data.length) yield { event, data: data.join('\n') };
          event = 'message'; data = [];
        } else if (line.startsWith('event:')) event = line.slice(6).trimStart();
        else if (line.startsWith('data:')) data.push(line.slice(5).replace(/^ /,''));
      }
      if (buffer.length > 65536 || data.join('').length > 65536) throw Error('STREAM_INTERRUPTED');
      if (part.done) break;
    }
  } finally { await reader.cancel().catch(()=>{}); reader.releaseLock(); }
}
