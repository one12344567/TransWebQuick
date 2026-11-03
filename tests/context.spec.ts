import {test,expect} from '@playwright/test';
test('membership, article and table send only their own semantic context',async({page},testInfo)=>{
 const queries:any[]=[];
 await page.route('**/api/lookup',async route=>{
  const input=route.request().postDataJSON();queries.push(input);
  const requestId=input.requestId;
  await route.fulfill({contentType:'text/event-stream',body:`event: delta\ndata: ${JSON.stringify({requestId,text:'<script>test</script> 释义'})}\n\nevent: done\ndata: ${JSON.stringify({requestId,finishReason:'stop'})}\n\n`});
 });
 await page.goto('/reading-lab');
 async function choose(selector:string){
  const el=page.locator(selector).first();await el.scrollIntoViewIfNeeded(); await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  await el.evaluate(el=>{const r=document.createRange();r.selectNodeContents(el);getSelection()!.removeAllRanges();getSelection()!.addRange(r);});
  await page.keyboard.press('Alt+KeyT');await expect(page.locator('#query-status')).toHaveText('已完成');
 }
 await choose('.plans li');
 expect(queries[0].sources.map((s:any)=>s.text).join(' ')).toContain('Basic');
 expect(JSON.stringify(queries[0])).not.toContain('data modeling');
 expect(JSON.stringify(queries[0])).not.toContain('Pro membership');
 await expect(page.locator('#answer')).toContainText('<script>test</script>');
 expect(await page.locator('#answer script').count()).toBe(0);
 await page.screenshot({path:testInfo.outputPath('lookup.png')});
 await page.locator('#detail').click();await expect(page.locator('#query-status')).toHaveText('已完成');
 expect(queries[1].mode).toBe('detail');expect(queries[1].sources).toEqual(queries[0].sources);
 await page.keyboard.press('Escape');
 await choose('tbody tr:first-child td:nth-child(3)');
 const sources=queries.at(-1).sources.map((s:any)=>s.text);
 expect(sources).toEqual(['shared pool','Messages','Plus']);
});
test('stream without terminal event is shown as incomplete',async({page})=>{
 await page.route('**/api/lookup',async route=>{
  const {requestId}=route.request().postDataJSON();
  await route.fulfill({contentType:'text/event-stream',body:`event: delta\ndata: ${JSON.stringify({requestId,text:'部分回答'})}\n\n`});
 });
 await page.goto('/reading-lab');
 await page.locator('#sample-one').evaluate(el=>{const r=document.createRange();r.selectNodeContents(el);getSelection()!.removeAllRanges();getSelection()!.addRange(r);});
 await page.keyboard.press('Alt+KeyT');await expect(page.locator('#query-status')).toContainText('未完成');
 await expect(page.locator('#retry')).toBeVisible();await expect(page.locator('#copy')).toBeDisabled();
});
test('late response cannot replace a newer selection',async({page})=>{
 let release:()=>void=()=>{};
 const gate=new Promise<void>(resolve=>release=resolve);
 let count=0;
 await page.route('**/api/lookup',async route=>{
  const {requestId}=route.request().postDataJSON();const number=++count;
  if(number===1) await gate;
  await route.fulfill({contentType:'text/event-stream',body:`event: delta\ndata: ${JSON.stringify({requestId,text:number===1?'OLD':'NEW'})}\n\nevent: done\ndata: ${JSON.stringify({requestId,finishReason:'stop'})}\n\n`}).catch(()=>{});
 });
 await page.goto('/reading-lab');
 async function select(selector:string){await page.locator(selector).evaluate(el=>{const r=document.createRange();r.selectNodeContents(el);getSelection()!.removeAllRanges();getSelection()!.addRange(r);});await page.keyboard.press('Alt+KeyT');}
 await select('#sample-one');await expect.poll(()=>count).toBe(1);
 await select('#sample-two');await expect(page.locator('#answer')).toHaveText('NEW');
 release();await expect(page.locator('#answer')).toHaveText('NEW');
});
test('direct meaning and explanation have distinct visual hierarchy',async({page},testInfo)=>{
 await page.route('**/api/lookup',async route=>{
  const {requestId}=route.request().postDataJSON();
  const chunks=['那是值得坚持到底的立场。\r','\n\r\n','“hill to die on” 指愿意为之坚持的立场。<script>不会执行</script>'];
  await route.fulfill({contentType:'text/event-stream',body:chunks.map(text=>`event: delta\ndata: ${JSON.stringify({requestId,text})}\n\n`).join('')+`event: done\ndata: ${JSON.stringify({requestId,finishReason:'stop'})}\n\n`});
 });
 await page.goto('/reading-lab');
 await page.locator('#sample-three').scrollIntoViewIfNeeded();
 await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
 await page.locator('#sample-three').evaluate(el=>{const r=document.createRange();r.selectNodeContents(el);getSelection()!.removeAllRanges();getSelection()!.addRange(r);});
 await page.keyboard.press('Alt+KeyT');
 await expect(page.locator('#query-status')).toHaveText('已完成');
 await expect(page.locator('.answer-meaning')).toHaveText('那是值得坚持到底的立场。');
 await expect(page.locator('.answer-meaning')).toHaveCSS('font-size','18px');
 await expect(page.locator('.answer-explanation')).toContainText('“hill to die on”');
 await expect(page.locator('.answer-explanation')).toHaveCSS('font-size','14px');
 await expect(page.locator('#answer script')).toHaveCount(0);
 await page.screenshot({path:testInfo.outputPath('answer-hierarchy.png')});
});
