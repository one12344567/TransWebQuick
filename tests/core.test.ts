import { test } from 'node:test';
import assert from 'node:assert/strict';
import {events,validate,type Lookup} from '../src/shared/protocol.ts';
import {cacheKey,Cache} from '../src/server/cache.ts';
const request:Lookup={requestId:'test',mode:'brief',selectedText:'DM',language:'zh-CN',contextVersion:'v1',contextStatus:'complete',contextTruncated:false,sources:[{id:'s1',kind:'paragraph',text:'DM is data modeling.'}]};
test('SSE preserves UTF-8 split at every byte and multiple CRLF events',async()=>{
 const bytes=new TextEncoder().encode('event: delta\r\ndata: {"text":"中文"}\r\n\r\nevent: done\ndata: {}\n\n');
 const stream=new ReadableStream<Uint8Array>({start(c){for(const b of bytes)c.enqueue(new Uint8Array([b]));c.close();}});
 const out=[];for await(const event of events(stream))out.push(event);
 assert.deepEqual(out,[{event:'delta',data:'{"text":"中文"}'},{event:'done',data:'{}'}]);
});
test('validator rejects budget, duplicate sources and arbitrary mode; strips extra fields',()=>{
 assert.throws(()=>validate({...request,selectedText:'a'.repeat(1001)}));
 assert.throws(()=>validate({...request,mode:'arbitrary'}));
 assert.throws(()=>validate({...request,sources:[request.sources[0],request.sources[0]]}));
 assert.throws(()=>validate({...request,sources:[{...request.sources[0],text:'a'.repeat(5001)}]}));
 assert.equal('apiKey' in validate({...request,apiKey:'not-a-real-key'}),false);
});
test('cache separates context, mode, model; ignores request ID and skips empty output',()=>{
 const key=cacheKey(request,'model');
 assert.equal(key,cacheKey({...request,requestId:'different'},'model'));
 assert.notEqual(key,cacheKey({...request,mode:'detail'},'model'));
 assert.notEqual(key,cacheKey({...request,sources:[{id:'s1',kind:'paragraph',text:'DM is direct messaging.'}]},'model'));
 assert.notEqual(key,cacheKey(request,'another-model'));
 const cache=new Cache();cache.set(key,{text:' ',returnedModel:'model'});assert.equal(cache.get(key),undefined);
 cache.set(key,{text:'数据建模',returnedModel:'model'});assert.equal(cache.get(key)?.text,'数据建模');
});
