import { test, expect, type Page } from '@playwright/test';
async function select(page: Page, selector = '#sample-one') {
  await page.locator(selector).evaluate(el => {
    const range = document.createRange(); range.selectNodeContents(el);
    getSelection()!.removeAllRanges(); getSelection()!.addRange(range);
  });
}
async function force(page: Page, selector: string) {
  await page.locator(selector).scrollIntoViewIfNeeded();
  return page.locator(selector).evaluate(el => {
    const range = document.createRange(); range.selectNodeContents(el);
    const box = range.getClientRects()[0];
    const options = { bubbles: true, cancelable: true, clientX: box.left + 3, clientY: box.top + box.height / 2 };
    const begin = new MouseEvent('webkitmouseforcewillbegin', options);
    el.dispatchEvent(begin);
    el.dispatchEvent(new MouseEvent('webkitmouseforcedown', options));
    el.dispatchEvent(new MouseEvent('webkitmouseforcedown', options));
    return begin.defaultPrevented;
  });
}
test.beforeEach(async ({ page }) => { await page.goto('/reading-lab'); });
test('ordinary click does not query; keyboard reads cross-tag selection and Escape closes', async ({ page }) => {
  await page.locator('#sample-one').click();
  await expect(page.getByRole('dialog')).toBeHidden();
  await select(page);
  await page.keyboard.press('Alt+KeyT');
  await expect(page.locator('#selected-text')).toContainText('DM limits');
  await expect(page.locator('#trigger-source')).toContainText('键盘调试');
  await expect(page.locator('#close')).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toBeHidden();
});
test('force sequence is deduplicated and synthetic events never claim hardware support', async ({ page }) => {
  await select(page);
  expect(await force(page, '#sample-one')).toBe(true);
  await expect(page.locator('#open-count')).toHaveText('1');
  await expect(page.locator('#trigger-source')).toContainText('合成事件');
  await expect(page.locator('#support')).toHaveText('真实重按未验证');
});
test('disabled and editable regions are not intercepted', async ({ page }) => {
  expect(await force(page, '[contenteditable]')).toBe(false);
  await page.locator('#enabled').uncheck();
  expect(await force(page, '#sample-one')).toBe(false);
  await expect(page.getByRole('dialog')).toBeHidden();
});
test('old selection in another region does not override the new point', async ({ page }) => {
  await select(page);
  await force(page, '#sample-two');
  await expect(page.locator('#selected-text')).toHaveText('In');
});
test('target removal and outer scroll close popover', async ({ page }) => {
  await select(page); await page.keyboard.press('Alt+KeyT');
  await page.locator('#sample-one').evaluate(el => el.remove());
  await expect(page.getByRole('dialog')).toBeHidden();
  await select(page, '#sample-two'); await page.keyboard.press('Alt+KeyT');
  await page.evaluate(() => document.dispatchEvent(new Event('scroll')));
  await expect(page.getByRole('dialog')).toBeHidden();
});
test('local server rejects foreign host/origin and private file paths', async ({ request }) => {
  expect((await request.get('/api/health')).status()).toBe(200);
  expect((await request.get('/api/health', { headers: { Origin: 'https://evil.example' } })).status()).toBe(403);
  expect((await request.get('/api/health', { headers: { Host: 'evil.example' } })).status()).toBe(403);
  expect((await request.get('/.env')).status()).toBe(404);
  expect((await request.post('/api/health')).status()).toBe(405);
});
test('export includes honest pending verdict and no selected text', async ({ page }) => {
  await select(page); await page.keyboard.press('Alt+KeyT'); await page.keyboard.press('Escape');
  const download = page.waitForEvent('download'); await page.locator('#export').click();
  const result = await download;
  const stream = await result.createReadStream();
  const chunks = []; for await (const chunk of stream!) chunks.push(chunk);
  const text = Buffer.concat(chunks).toString();
  expect(JSON.parse(text).verdict).toBe('pending-human-review');
  expect(text).not.toContain('higher DM');
});
