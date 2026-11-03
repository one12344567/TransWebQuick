import { validate } from '../shared/protocol.ts';
import { translate, promptVersion } from './deepseek.ts';
import { Cache, cacheKey } from './cache.ts';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const port = Number(process.env.PORT || 8787);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT 必须是 1–65535 的整数');
const authority = `127.0.0.1:${port}`;
const files: Record<string, [string, string]> = {
  '/': ['public/reading-lab.html', 'text/html; charset=utf-8'],
  '/reading-lab': ['public/reading-lab.html', 'text/html; charset=utf-8'],
  '/style.css': ['public/style.css', 'text/css; charset=utf-8'],
  '/client.js': ['dist/client.js', 'text/javascript; charset=utf-8'],
};
const root = fileURLToPath(new URL('../../', import.meta.url));
const cache = new Cache();
const model = process.env.DEEPSEEK_MODEL || 'deepseek-flash';
const server = createServer(async (req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'");
  if (req.headers.host !== authority || (req.headers.origin && req.headers.origin !== `http://${authority}`)) {
    res.writeHead(403).end('Forbidden'); return;
  }
  const lookupPath = req.url === '/api/lookup';
  if (lookupPath && req.method === 'POST') {
    if (req.headers['content-type']?.split(';')[0].trim() !== 'application/json') { res.writeHead(400, {'Content-Type':'application/json'}).end(JSON.stringify({code:'INVALID_REQUEST'})); return; }
    let input;
    try {
      const chunks: Buffer[] = []; let size=0;
      for await(const chunk of req) { size+=chunk.length; if(size>65536) { res.writeHead(413).end(); return; } chunks.push(chunk); }
      input=validate(JSON.parse(Buffer.concat(chunks).toString('utf8')));
    } catch { res.writeHead(400, {'Content-Type':'application/json'}).end(JSON.stringify({code:'INVALID_REQUEST'})); return; }
    res.writeHead(200, {'Content-Type':'text/event-stream', 'X-Accel-Buffering':'no'});
    const controller=new AbortController(); res.on('close',()=>controller.abort());
    const started=performance.now(); let firstTextMs:number|null=null;
    const send=(event:string, value:object)=>{ if(!res.destroyed) res.write(`event: ${event}\ndata: ${JSON.stringify({requestId:input.requestId,...value})}\n\n`); };
    const key=cacheKey(input,model); const hit=cache.get(key);
    send('meta',{cached:!!hit,requestedModel:model,promptVersion});
    try {
      if(!process.env.DEEPSEEK_API_KEY) throw Error('CONFIG_MISSING');
      const result=hit || await translate(input,controller.signal,text=>{ firstTextMs ??= performance.now()-started; send('delta',{text}); },model);
      if(controller.signal.aborted) return;
      if(hit) send('delta',{text:hit.text}); else cache.set(key,result);
      send('done',{finishReason:'stop',returnedModel:result.returnedModel,totalMs:Math.round(performance.now()-started),firstTextMs,cached:!!hit});
    } catch(error) {
      const code=error instanceof Error?error.message:'UPSTREAM_ERROR';
      if(code!=='CANCELLED') send('error',{code});
    } finally { res.end(); }
    return;
  }
  if (req.method !== 'GET') { res.writeHead(405, { Allow: 'GET' }).end(); return; }
  const path = new URL(req.url || '/', `http://${authority}`).pathname;
  if (path === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ ready: true, stage: 'M2', keyConfigured: !!process.env.DEEPSEEK_API_KEY, requestedModel:model })); return;
  }
  const file = files[path];
  if (!file) { res.writeHead(404).end('Not found'); return; }
  try {
    const body = await readFile(root + file[0]);
    res.writeHead(200, { 'Content-Type': file[1] }).end(body);
  } catch { res.writeHead(500).end('Build missing. Run npm run build.'); }
});
server.on('error', (error: NodeJS.ErrnoException) => {
  console.error(error.code === 'EADDRINUSE' ? `端口 ${port} 已被占用。使用 PORT=8788 npm run dev。` : `启动失败：${error.code}`);
  process.exitCode = 1;
});
server.listen(port, '127.0.0.1', () => console.log(`TransWebQuick: http://${authority}/reading-lab`));
