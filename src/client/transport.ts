import { events, type Lookup } from '../shared/protocol.ts';
export async function lookup(input:Lookup,signal:AbortSignal,onEvent:(event:string,value:any)=>void) {
  const response=await fetch('/api/lookup',{method:'POST',signal,headers:{'Content-Type':'application/json'},body:JSON.stringify(input)});
  if (!response.ok) { const value=await response.json().catch(()=>({code:'UPSTREAM_ERROR'})); throw Error(value.code || 'UPSTREAM_ERROR'); }
  if (!response.body) throw Error('STREAM_INTERRUPTED');
  let done=false;
  for await(const event of events(response.body)) {
    const value=JSON.parse(event.data);
    if(value.requestId!==input.requestId) continue;
    if(event.event==='error') throw Error(value.code);
    onEvent(event.event,value);
    if(event.event==='done') { done=true; break; }
  }
  if(!done) throw Error('STREAM_INTERRUPTED');
}
