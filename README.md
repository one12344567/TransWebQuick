# TransWebQuick

Safari 原地语境释义原型。按《Safari 重按语境释义原型开发文档》v1.0 推进。

当前阶段：M0 真实 Force Touch 验证工具已实现，**真机验收待执行**。没有接入模型，没有生成真实释义。按需求第 4、15 节，M0 通过后再推进 M1–M4。快捷键和合成事件不能证明真实重按有效。

## 本地运行

使用 Node.js 24（本机已验证 24.14.0）。所有依赖安装在项目目录。

```sh
npm ci
npm run dev
```

Safari 打开 http://127.0.0.1:8787/reading-lab 。替代端口：`PORT=8788 npm run dev`。
服务仅监听 127.0.0.1，检查 Host / Origin，不开放 CORS，不访问模型或保存查询历史。

## M0 验证

1. 保持「本页重按释义」开启。在正文单词上真实重按，再选中 `DM limits` 重按。
2. 查看是否只出现自定义浮窗，事件日志是否包含 `isTrusted: true` 的 `webkitmouseforcewillbegin`、`webkitmouseforcedown`，且前者 `defaultPrevented: true`。
3. 连续轻点、拖选、轻点链接应正常；按钮、输入框、可编辑区重按不接管。
4. 旧选区留在另一段时重按新词；浮窗应选择新词。按 Esc、点击外部、滚动或切走标签应关闭。
5. 关闭开关，对比系统原生查询行为；填写设备、Safari 完整版本、触控板和系统查询设置，以及是否出现系统浮窗。
6. 点击「导出验证记录」，保存 JSON 后交给开发者核对。可信事件和人工观察需一起判断，页面不会自动宣布 M0 通过。

Option+T：选中文本后调试浮窗（非真实重按）；若与 Safari 快捷键冲突，使用正文下方调试按钮。不会拦截输入区域的快捷键。

## 开发检查

```sh
npm run check
npm test
```

自动测试使用 Chromium 验证逻辑和交互，不等同于 Safari 硬件验收。首次测试安装浏览器：`npx playwright install chromium`。

目录：`src/client` 交互与选区，`src/server` 本机服务，`tests` 自动测试，`docs` 验收与里程碑。`dist` 自动构建，不提交。

## 后续阶段

- M1：完整阅读实验页、语义上下文、浮窗和调试面板。
- M2：DeepSeek 本机转发、非思考模式、流式响应和主动展开；届时才需要本机配置 `DEEPSEEK_API_KEY`。
- M3：语境缓存、取消并发、预算、安全与错误处理。
- M4：24 项用例、36 次语义评审、30 次冷请求与 10 次缓存请求统计。

当前不需要 Xcode；Safari 扩展打包属于原型验收后的独立阶段。API 密钥不得写入源码、浏览器存储或提交 Git。

若本机已有 Google Chrome，可用 `PLAYWRIGHT_CHANNEL=chrome npm test`，无需另行下载测试浏览器。自动测试使用临时浏览器配置，不使用日常浏览器资料。
