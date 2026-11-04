# PressTrans 在线服务与语言设置

更新：2026-11-04。English quick start follows below.

## 先选语言

在「通用 → 界面语言」选择跟随系统、English、简体中文或繁體中文。界面语言不影响译文语言。

在「翻译 → 语言偏好」分别设置译文和解释语言。默认译文跟随系统，解释与译文相同。原文会自动识别；原文已是目标语言时默认直接释义，也可开启「翻译为另一种语言」。例如：日文 → 英文译文 + 法文解释；中文 → 英文译文 + 中文解释。列表以外的语言可选择「其他语言」并输入语言名称。具体质量取决于模型。

语言列表始终使用各语言自己的名称，例如简体中文、繁體中文、日本語、한국어、Français、العربية；菜单和已选值保持一致，不随界面语言改为英文。

离线词典目前仅提供英语到简体中文的释义。选择其他目标语言时不会用中文词典结果替代目标译文；断网或服务失败会明确提示。界面提供三种语言，并不意味着所有国家的界面语言都已经完成翻译。

## 配置流程

1. 在服务商的官方网站注册 API 账户、创建 API Key，并确认账户可用额度与模型权限。聊天应用的会员不一定包含 API 额度。
2. 打开「服务 → 配置…」，选择服务商。PressTrans 会填入地址和模型示例。
3. 检查 Base URL、模型名称，输入该服务商的 API Key，点击「保存」。只有保存成功才会生效。
4. 在「服务」开启「在线释义」。在「手动查询」输入 `Hello`，点击查询，检查返回语言与设置一致。

服务页的「查看效果」、手势演示以及「界面」中的浮窗预览均为预设内容，不会调用 API 或消耗 token。验证账户和网络连通性需要主动执行一次真实查询。

默认服务为 DeepSeek，不需要自建或租用中转服务器。自定义服务必须兼容 **OpenAI Chat Completions + SSE 流式输出**；不直接支持只提供 Anthropic Messages 或 OpenAI Responses 的地址。

## 服务预设

| 服务 | Base URL | 模型示例 | 官方配置文档 |
| --- | --- | --- | --- |
| DeepSeek（默认） | `https://api.deepseek.com` | `deepseek-flash` | [首次调用](https://api-docs.deepseek.com/) |
| OpenAI | `https://api.openai.com/v1` | `gpt-4.1-mini` | [Chat Completions](https://developers.openai.com/api/reference/resources/chat) |
| 阿里云百炼（北京） | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus` | [获取 API Key](https://help.aliyun.com/zh/model-studio/get-api-key)、[地域与地址](https://docs.bailian.console.aliyun.com/en/model-studio/base-url) |
| Moonshot / Kimi | `https://api.moonshot.cn/v1` | `kimi-k3.1-pro` | [快速开始](https://platform.kimi.com/docs/get-api-key) |

这些是可编辑的起点，并非所有模型、账户和地域的兼容性保证。模型可能更名或退出服务，以控制台当前名称为准。百炼的 Key、模型和 Base URL 必须属于对应地域；使用国际站时请按官方地域表修改地址。Kimi 等推理模型可能消耗较多输出额度或超过当前 30 秒请求时限，短文本翻译优先选择可快速输出最终答案的模型。

## 自定义地址

选择 Custom，填入服务给出的兼容地址、模型 ID 和密钥。例如 `https://example.com/v1`。PressTrans 自动追加 `/chat/completions`；已经填写完整端点时不会重复追加。保留供应商要求的 `/v1` 或 `/compatible-mode/v1` 路径。

支持 HTTPS；本机开发服务允许 `http://127.0.0.1:端口/v1` 或 `http://localhost:端口/v1`。无鉴权的本地兼容服务可以填写占位 Key（例如 `local-only`），前提是服务端接受它。地址中不能夹带账号、密码、查询参数或片段。

## 密钥与数据

密钥只写入 `~/Library/Application Support/PressTrans/provider.json`，文件权限为当前用户读写，不存入项目或 Git。该文件不是加密保险箱。密钥绑定保存时的完整服务端点，修改端点必须重新保存该服务的密钥；应用不会自动沿 HTTP 重定向转发请求。

当前只保存一套正在使用的服务配置，切换服务并保存会替换原配置。在线查询时，选中文字和附近上下文直接发送到配置的服务商；OCR 图像不上传。请不要把密钥贴到公开文档、截图或反馈中。

“界面 → 清晰高亮”在已有录屏授权时，也会读取目标文字的小块本地画面，用于贴合字形、保持文字清晰；不保存、不上传，不消耗 token。它与取词失败时的 OCR 回退相互独立，可单独关闭。

## 排查

“用量”页从 0.5 版起记录每次在线调用，展开浮窗也可看到本次总量。输入、输出及缓存命中来自服务商返回的 `usage`，不会额外发起统计请求。实现同时处理 [DeepSeek 的最后一个内容块](https://api-docs.deepseek.com/api/create-chat-completion/)和 [OpenAI 的独立 usage 块](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)。请求启用 `stream_options.include_usage`，自定义服务需支持该兼容参数。断流、取消或服务未返回用量时标为“未返回”，不代表免费；以服务商账单为准。

- 保存失败：检查 HTTPS 地址、模型名和非空 Key，地址中不要带 `?` 参数。
- 无在线结果：确认「在线释义」已开启，密钥已经保存，账户有额度且模型 ID 可用。
- 401 / 403：核对 Key、所属服务与模型权限；429：检查额度或稍后重试。
- 404：核对 Base URL 路径及模型名称，不能填服务商的网页聊天地址。
- 回答被截断或一直等待：尝试更快的非推理模型。当前短释义最多 600、详细释义最多 900 个输出 token，部分推理模型可能因此无法返回完整答案。
- 切换界面语言不会翻译已经显示的模型回答；重新查询即可使用新的翻译偏好。

## English quick start

Choose the app language in **General → App language**. English, Simplified Chinese and Traditional Chinese are available, with a system-language default (English fallback). Choose translation and explanation languages independently in **Translation**. Source detection is automatic. “Other language” accepts a language name beyond the presets.

In **Services → Configure…**, select a provider, verify its Base URL and model ID, enter that provider's API key and choose **Save**. Enable online translation in **Services** and try `Hello` in **Manual Lookup**. The table above links to each provider's official documentation. DeepSeek is the default; no relay server is required.

Custom services must support OpenAI-compatible Chat Completions with streaming SSE. The app appends `/chat/completions` once. Remote URLs require HTTPS; loopback HTTP is supported for local services. Provider regions, model access and API billing must match your account. Chat subscriptions do not necessarily include API credit.

Only one active service configuration is stored. Keys are kept in the app's local data folder, bound to the saved endpoint, and never forwarded through redirects. Changing endpoints requires saving a key again. The offline dictionary supports **English → Simplified Chinese only**. Other language pairs require a working online service. Provider presets have not all been tested with paid accounts.

**Appearance → Clear text highlight** also reads a small local text crop when screen recording is already authorized, independently of OCR fallback. It preserves glyph contrast and trims the highlight, saves/uploads no images and uses no tokens. It can be disabled separately.
