# TransWebQuick

Safari 原地语境释义本地原型，按开发文档 v1.0 推进。

当前：真实单词重按和跨标签 `DM limits` 选区已获用户真机确认；本地阅读页、上下文提取、DeepSeek 流式释义、展开解释、复制、重试及语境缓存已实现。完整 M4 验收尚未完成，不是已打包的 Safari 扩展。

## 启动

Node.js 24（已验证 24.14.0）：

```sh
npm ci
cp .env.example .env   # 仅首次；已有 .env 时不要覆盖
# 在本机编辑 .env，填写 DEEPSEEK_API_KEY
npm run dev
```

用 Safari 打开 http://127.0.0.1:8787/reading-lab 。端口冲突可运行 `PORT=8788 npm run dev`。改代码后重启开发服务会重新构建前端。

`.env` 已被 Git 忽略，密钥只由服务端加载。不要提交密钥、上传本地测试记录或把真实密钥粘进前端。

## 使用

在阅读区域重按单词，或拖选短语后重按。上方宣传标题保留系统查询；按钮、输入框和编辑器不接管。

- 首次查询：第一段直接给出释义，后续解释另起一段；主释义以更大字号显示。
- 参考上下文：查看本次请求使用的本地原文片段。
- 展开解释：复用原上下文快照，主动发起详细释义请求。
- 复制：仅复制已完成的释义，不读取剪贴板。
- Esc、点击外部、外部滚动、切换标签、目标移除或文字改变：关闭并取消当前请求。
- 重试：只由用户主动点击触发；中断结果显示“未完成”，不缓存。
- Option+T 或选区调试按钮：辅助调试，不能代替真实 Force Touch 验收。

默认隐藏事件诊断，访问 `/reading-lab?debug=1` 显示事件日志。人工观察区可导出设备信息、手势事件及成功请求计时，不导出正文或密钥。真实测试内容默认仅留在被忽略的 `local-records/`。

## 本机服务

同一服务提供静态页面与 `POST /api/lookup`，只绑定 127.0.0.1，校验 Host / Origin，不开放 CORS。请求为 JSON，最大 64 KiB；选区最多 1000 Unicode 码点，来源最多 6 个 / 5000 码点。白名单字段构造模型输入，客户端不能指定系统提示词、上游地址或密钥。

使用 DeepSeek 官方 HTTPS `/chat/completions`，默认 `deepseek-flash`，显式关闭 thinking，brief/detail 输出预算 256/512 tokens。没有密钥时仍能浏览页面，查询给出配置提示。

SSE 返回 meta、delta、done 或 error。缓存键包括上下文、模式、版本和模型配置；内存 LRU 上限 200 条、TTL 30 分钟，只缓存完整成功结果。首字、闲置、总超时分别为 15、10、30 秒。流中断与截断均不视为成功。

## 测试

```sh
npm run check
npx playwright install chromium  # 首次，无现成 Chrome 时
npm test
# 已安装 Google Chrome 时可直接：
PLAYWRIGHT_CHANNEL=chrome npm test
```

自动测试中的界面模型响应为模拟数据，不消耗 API 额度；浏览器使用独立临时配置。Chromium 测试不能替代 Safari 真机手势验收。

代码目录：`src/client` 页面交互和上下文，`src/server` 服务与模型适配，`src/shared` 协议和流解析，`tests` 自动测试，`fixtures` 独立语义答案，`docs` 验收状态。

## 剩余验收与限制

见 `docs/acceptance.md`。当前不支持 iframe、Shadow DOM、Canvas、图片 OCR、PDF 或跨应用查询；不会全局修改系统词典。长段落采用局部裁剪，通用提取策略仍需更多复杂 DOM 评估；单词跨文本节点自动扩词尚未实现，可手动选择完整短语。详细展开和非原生缩放下的布局需 Safari 实测。429 显示限流提示，尚未实现 Retry-After 倒计时。

按用户 2026-11-03 指示，本轮不追查上游网络延迟；保留超时处理，速度指标暂缓验收。完整 24 项用例、36 次语义评审和 30 冷 / 10 热性能样本尚未完成。Safari 扩展与 X 网站适配属于后续阶段。
