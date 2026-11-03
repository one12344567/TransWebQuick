import {test} from 'node:test';
import assert from 'node:assert/strict';
import {translate} from '../src/server/deepseek.ts';
import type {Lookup} from '../src/shared/protocol.ts';
const input:Lookup={requestId:'test',mode:'brief',selectedText:'DM',language:'zh-CN',contextVersion:'v1',contextStatus:'complete',contextTruncated:false,sources:[{id:'s1',kind:'paragraph',text:'DM means data modeling.'}]};
test('upstream authentication, rate limit, truncated and interrupted outputs are sanitized',async()=>{
 const original=globalThis.fetch;
 try {
  for(const [status,code] of [[401,'UPSTREAM_AUTH'],[429,'UPSTREAM_RATE_LIMIT']] as const){
   globalThis.fetch=async()=>new Response('sensitive upstream diagnostic',{status});
   await assert.rejects(translate(input,new AbortController().signal,()=>{},'test'),new Error(code));
  }
  for(const [reason,code] of [['length','INVALID_OUTPUT'],[null,'STREAM_INTERRUPTED']] as const){
   globalThis.fetch=async()=>new Response(`data: ${JSON.stringify({model:'test',choices:[{delta:{content:'partial'},finish_reason:reason}]})}\n\ndata: [DONE]\n\n`);
   await assert.rejects(translate(input,new AbortController().signal,()=>{},'test'),new Error(code));
  }
 }finally{globalThis.fetch=original;}
});
