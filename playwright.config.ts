import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests', use: { baseURL: 'http://127.0.0.1:8787', headless: true, channel: process.env.PLAYWRIGHT_CHANNEL },
  webServer: { command: 'npm run dev', url: 'http://127.0.0.1:8787/api/health', reuseExistingServer: !process.env.CI },
});
