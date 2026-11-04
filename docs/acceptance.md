# 验收记录

依据用户提供的开发文档 v1.0（2026-11-03）。当前只实现 M0，后续里程碑未验收。

## 环境

- 实测宿主：Apple Silicon / macOS 27.2 (26B118)。
- Node.js：24.14.0。Xcode：仅 Command Line Tools，完整 Xcode 尚未安装。
- Safari 完整版本、Mac 型号、触控板、系统设置、缩放：待人工记录。
- 模型调用：未启用；性能与语义结果：未采集。

## M0 通过条件

真实设备上取得可信 forcewillbegin / forcedown，前者正确取消默认动作，正文只出现一个自定义浮窗；普通轻点和拖选不受影响；按钮、输入框和编辑器不接管。人工确认系统词典不叠加。不能以模拟事件、快捷键或仅检查属性存在代替真机结论。

状态：**已收到用户截图中的真实重按成功证据，完整 M0 验收仍待补齐**。页面可导出事件与人工观察 JSON；下载文件默认不提交仓库。

## 正式用例状态

T01–T12 语义与选区：未执行（M1/M2）。T13–T16 真机手势：T14 已有正文真实重按成功截图，其余观察及事件记录待补齐。T17 请求并发：未实现。T18 Esc / 滚动：本地关闭可自动验证，上游取消未实现。T19 四角定位：基础实现，正式验收待执行。T20–T23 上游错误、缓存、流解析、提示注入：未实现。T24 节点失效与键盘：基础逻辑可自动验证，Safari 正式验收待执行。

## 已知限制

M0 无跨文本节点自动扩词（手动跨标签选区可读取），无完整上下文提取、模型流和缓存；不支持 iframe / Shadow DOM。缩放或调整窗口尺寸时关闭浮窗。调试日志保留最近 300 条事件，不保留正文。自动测试只验证浏览器逻辑。

## 后续实现约定

选区 1000 Unicode 码点，来源最多 6 段 / 共 5000 码点；本机 POST /api/lookup，64 KiB 限额；SSE meta/delta/done/error；只缓存完整成功输出。密钥仅服务端环境变量。模型参数在 M2 开始时重新查 DeepSeek 官方资料。源文档中的示例模型映射并非已实测结论。

## 本次自动验证

2026-11-03：`npm run check` 通过；`PLAYWRIGHT_CHANNEL=chrome npm test` 共 7 项通过（3.5 秒），使用独立临时 Chrome 配置。覆盖普通点击不查询、跨标签选区和 Esc、合成手势去重、禁用及编辑区、旧选区隔离、节点移除及滚动关闭、Host/Origin 和路径限制、无正文的记录导出。以上结果不代表 Safari 真机手势验收。

## 用户真机观察（2026-11-03）

用户提供两张截图：上方宣传标题“原文”出现系统词典；阅读样本中的 limits 出现本项目浮窗，标注“真实重按事件”。该差异符合 M0 的区域限定：宣传标题不在 data-query-region 内，阅读样本才接管。第二张截图中未见系统词典叠加，但不能由单张截图推定所有手势序列均已通过。

接下来核对手动选中 DM limits 后重按能否保留完整短语；轻点、拖选及链接是否正常；正文查询是否一直不叠加系统词典。仍需导出的可信事件日志和设备信息。只保存上述文字观察，不提交包含用户浏览器标签的原始截图。页面已增加区域说明，未扩大手势接管范围。

## 2026-11-03 后续进展

用户再次截图确认：手动跨 span/em 选择 DM limits 后，真实重按保留完整短语，自定义浮窗可见；用户回复“可以”。据此继续 M1/M2。尚未补齐原始事件导出、Safari 版本与所有普通交互观察，不能据此宣布全部 M0/M4 用例通过。

已实现 M1/M2 及部分 M3：复杂阅读测试页、语义来源与预算、同源 JSON 接口、DeepSeek 官方非思考流、纯文本渲染、参考上下文、复制、详细展开、取消与请求隔离、错误重试、完整结果内存 LRU。独立语义答案置于 fixtures，不对浏览器提供该文件。

真实调用记录（只保留脱敏摘要）：

- 私信样本完整返回，释义正确说明私信额度且没有编造数字。requestedModel / returnedModel 均为 deepseek-flash，首字约 600 ms，总时长 16043 ms，finishReason=stop。
- 数据建模样本只返回部分正文后触发 UPSTREAM_TIMEOUT；不视为成功，不缓存。总时长约 10252 ms。
- 这两个样本不构成语义评审或 P50/P95 报告。用户要求暂不追查网络延迟，未据此认定厂商宕机，不再追加线上请求。

当前测试集覆盖 UTF-8 逐字节分块、CRLF SSE、字段预算和非法输入、语境缓存隔离、跨标签选区、手势去重、排除区域、旧选区、取消后晚到结果、节点移除、表格语义、详情复用快照、纯文本渲染与断流错误。完整语义准确率、Safari 手势可靠性、100%/125% 布局、36 次人工评审与性能采样均待完成。

已知剩余项：429 Retry-After 倒计时；自动扩词跨文本节点；更多复杂 DOM 与跨段落映射测试；异常路径的完整端到端测试；触发至绘制的性能指标。当前导出只记录成功请求服务端计时，尚不是文档要求的完整性能报告。旧节中的“未实现”说明对应 M0 历史，本节为最新状态。

本轮验证结果：TypeScript 检查通过；4 项 Node 核心测试通过，10 项 Chromium 浏览器测试通过。已检查浮窗截图，选词与正文未被浮窗遮住；仅覆盖该测试视口，不替代 100%/125% Safari 验收。源码密钥扫描通过，.env 权限 600 且被 Git 忽略，本地真实调用原始记录也被忽略。

## 释义呈现调整（2026-11-03）

按用户反馈，将提示词升级为 meaning-v2：首段直接给出词义或译文，禁止“这句话的意思是”等介绍语；空行后补充语气、搭配与背景，brief/detail 均遵守。缓存键包含提示词版本，旧版结果不再命中。界面以 18px 主释义和 14px 补充解释显示，流式过程支持跨块换行；若模型没有分段，保留全文并退回普通正文样式，不猜测或删改语义。

验证：类型检查、构建、6 项核心测试和 11 项浏览器测试通过；已查看分层排版截图。新增测试覆盖段落分隔跨块、未分段回退、文字安全渲染及字号层级。未追加真实 DeepSeek 调用，模型遵守新版措辞的实际效果仍需后续查询观察。服务已重启以加载新版提示词。


## PressTrans 原生与离线阶段（2026-11-03）

新增 Swift/AppKit/SwiftUI 原生菜单栏应用，代码与构建说明见 native/README.md。包含非激活式浮窗、有限上下文 AX 读取、Option+Shift+T 快捷键、手动查询、可选直接 DeepSeek SSE、任务取消与结果隔离。默认离线，无需任何密钥。ECDICT 英汉词库固定版本、校验源哈希后构建成约 90.2 MB 的 SQLite，769032 条；应用包约 91 MB。词形、短语、可分离短语、分词释义与拼写建议均有明确匹配标识。

构建成功，核心检查与词库样本通过，另验证离线独立使用、模拟网络部分输出后失败的完整离线回退、在线成功替换和取消。已在原生 UI 中输入 turned it down，看到 turn down / 拒绝 的离线结果，并检查浮窗截图。未追加真实线上模型请求。默认包无开发 .env 配置路径，也不内置任何密钥。

本机尚未授予 PressTrans 辅助功能权限，跨应用选区与上下文尚不能声称已实测通过。全局重按、浏览器扩展、OCR、签名公证、Intel/8 GB 设备与长期资源增长测试未完成。网页阶段的手势验收不能代替上述原生验收。系统 NaturalLanguage 仅做独立资源评估，未加入正式依赖或查询路径；暂不加入本地生成模型。

## 原生入口、权限身份与实验重按（2026-11-03）

根据用户连续反馈，本轮改为固定项目本地代码签名（不添加系统信任），安装到 /Applications/PressTrans.app，并加入 ICNS 图标。设置窗口打开时显示 Dock，关闭后恢复菜单栏模式；菜单栏增加隐藏入口，重新打开应用可恢复设置。权限状态在设置可见时每秒更新，并在应用激活和查询时复查。

重按增加实验性的私有 MultitouchSupport 压力监听、公开 NSEvent 点击判定、AX 指针命中取词。提供系统/PressTrans 分段切换；启用前持久化三项系统查词偏好，失败回滚，关闭与正常退出恢复，异常终止后下次启动恢复。判定测试覆盖轻点、单次触发、双击、拖动、长按、释放；构建、原有词典与流回退检查通过。物理重按、系统设置实际生效及全局应用兼容性尚不能仅凭这些检查确认。

用户要求取消钥匙串弹窗，已移除供应商配置的所有 Security/Keychain API 访问。现使用用户 Application Support/PressTrans/provider.json，目录 0700、文件 0600、原子保存；已有 .env 测试密钥仅本机迁入，新版启动未再弹钥匙串密码框。代码与忽略规则扫描通过，私有配置和签名材料均未加入 Git。

本机系统权限页中的旧 PressTrans 开关为开，但运行应用实际权限检查失败。用户已明确同意将旧条目重新绑定到安装版。系统 Touch ID 验证需由用户完成；在完成前，不宣称权限问题或真实重按已验收通过。

## 原生全局取词与界面复验（2026-11-03）

辅助功能授权已重新绑定安装版并在应用内确认有效；录屏权限经用户明确同意，已在系统与应用内确认开启。之前验证过系统查词切换前后的三个偏好键逐项恢复一致。物理压力可靠性仍须单独验收。

设置重做为侧栏与原生分组表单，支持窗口缩放、Command-W、Dock 随设置窗口显示。浮窗使用 AppKit 材质、箭头与独立黄色高亮；截图检查已完成设置与预览浮窗，跨应用高亮动画仍不等于完整物理手势验收。

新增不设应用白名单的 AX 文本标记、字符范围、有限文字叶节点字词边界查询，以及可选本地 OCR 回退。正式构建不包含指定应用的测试控件。因计算机工具的定向按键未触发 Carbon 全局热键、窗口操作未同步系统前台，使用 `PRESSTRANS_CAPTURE_ACCEPTANCE=1 bash scripts/build-native.sh` 的临时 UI 调用真实应用同一个 TextCapture 实现；记录以下 **接口集成测试**，不冒充物理重按端到端验收：

| 真实窗口与操作 | 结果 |
| --- | --- |
| Safari example.com 正文未选中的 documentation | 正确单词、完整段落、bounds=true，6 ms |
| Safari example.com 选中 documentation examples | 修复标记起点后正确短语、完整段落、bounds=true，5 ms |
| Safari X 订阅页标题 subscription | 正确单词、标题上下文、bounds=true，13 ms |
| Safari X 换行链接 anytime | 正确单词、所在条款段落、bounds=true，3 ms |
| Safari X 同一链接第一行 Cancel 的测试坐标 | 未读取成功，保留为待查项 |
| Chrome example.com 未选中 documentation | 补充字词边界适配后正确单词、完整段落、bounds=true，19 ms |
| Chrome example.com 选中 documentation examples | 正确短语、完整段落、bounds=true，3 ms |
| Chrome 正文上方空白区域 | 正确拒绝，没有误抓邻近文字 |

本地 Vision 图片检查通过：精确识别 limits、同一行上下文、Retina 2x / 负屏幕原点坐标映射、空白拒绝。首次进程观察到 28.4 秒初始化；再次启动同样检查为 82 ms，不能视为所有设备冷启动指标。真实 Chrome 窗口截图 OCR 集成尚未通过，正在核查截图裁剪与定位；正式 UI 标为实验功能，不能宣称图片/画布已普遍稳定。截图不落盘、不上传，纯本地识别。用户已选择开启 OCR 回退。

多语言提示策略、Unicode 取词、压力状态机、上下文预算、SSE、真实词典和在线失败回退/取消检查通过。之前的三次真实模型样本分别验证日语→中文、中文→英语+中文解释、中文仅释义。8 GB Intel、长时间运行、PDF/Canvas 和真实触控板全流程兼容矩阵仍未完成。

### 2026-11-04 · Two settings styles and compact lookup

- Native installed app: A/B style switching verified; B persists across application replacement/relaunch. Both use the same settings.
- Native lookup panel: default collapsed, expand explanation, expand source context, open copy menu, dismiss menu without losing panel, and collapse again verified through accessibility and screenshots. Expansion does not invoke the translator.
- Service configuration: fields appear only in a sheet; an edited model draft was cancelled and the saved model remained deepseek-flash. No provider request or secret change was needed.
- Layout follow-ups: fixed picker widths; moved source attribution into expanded context; removed the intrusive scroll indicator and added expanded text space.
- Found and fixed delayed interface language refresh by binding the picker directly to AppStorage. After unlock, native A and B English translation settings were visually checked without clipped labels. Switching back to Follow System refreshed all visible labels immediately; the original language setting was restored.
- Final installed popover recheck after unlock: expanded explanation and expanded context both render fully without the intrusive scrollbar or clipped bottom text. Preview was closed after checking. Style B remains selected for comparison; final product default is still undecided.
- Release build and installed signature verified. Core checks passed: Unicode/context, provider endpoints, pressure detector, OCR fixture, dictionary, streaming failure fallback and cancellation. This does not establish new real-hardware Force Click compatibility.

### 2026-11-04 · Appearance and preset demonstrations (0.4.0)

- A is now the requested default; the header A/B switch is removed. Appearance provides visual A/B cards, three lookup surfaces, three typefaces, text size, four ink palettes and bounded glass opacity. Verified A → B → A in the installed app and left A with default Glass/System/Automatic appearance selected.
- Visual checks confirmed aligned General controls, regular Liquid Glass menus without black arrow blocks, and visible font/color controls beside the live preview. Graphite + Serif + Ocean matched the real lookup popup. Preview and actual popup were closed after checking.
- Services replaces long inline descriptions with one local feature illustration. Privacy details remain in a separate sheet. Online, OCR and Force Click illustrations were each observed at their initial and final states; none changed the real feature toggles. Their code contains only fixed samples and finite, cancellable animation tasks, with no translator, provider, screen capture or credential dependency. These illustrations do not establish new real-hardware gesture or OCR compatibility.
- Accessibility paths use opaque surfaces for Reduce Transparency / Increase Contrast and the completed illustration for Reduce Motion. Those system modes, older macOS fallback and an English layout of the new Appearance page have not been visually retested in this pass.
- Release build and installed signature passed. The existing core checks passed in the normal host environment, including the local OCR raster fixture, Unicode/context, provider policy, pressure detector, dictionary and stream fallback/cancellation. The restricted execution attempt could not create a Vision pixel buffer; rerunning outside that restriction passed. No paid API call was used.

### 2026-11-04 · Native language names (0.4.1)

- Translation, explanation and alternate-language pickers share native language labels for all 21 presets (简体中文, 日本語, 한국어, Français, العربية, etc.). Stored values and translation policy remain unchanged; custom language names pass through as entered.
- Release build and installed signature passed. The installed translation menu and its selected 简体中文 label were visually checked; the existing language choice was preserved. No API request was needed.

### 2026-11-04 · AI-first lookup, usage history and reveal refinement (0.5.0)

- Pipeline checks cover a blank loading state before AI text, no local lookup before AI completion, a separate dictionary reference, complete offline fallback after partial stream failure, offline-only operation and cancellation during a stream.
- Usage checks cover DeepSeek's finish chunk and OpenAI's empty-choices usage chunk, absent/malformed counters, cached/reasoning fields, idempotent updates, reported usage on failed requests, unknown cancelled requests, persistence, interrupted-request recovery and pagination. A 1,000-record fixture occupies 184,320 bytes; the file is 0600. Fixtures are temporary and do not appear in the user's ledger.
- One real official DeepSeek request for `book` through the production Translator + LookupEngine returned 293 input / 55 output / 348 total tokens. The trace contained loading, AI stream, completion and dictionary reference, with no preceding dictionary answer. This is a network/pipeline integration check using a local runner, not a claim that a physical Force Click was automated.
- The installed Usage page visibly shows the same request, its expanded counts and 16 KB file size. The replacement local illustration was observed from `day / 一天；白天` to `You made my day. / 你让我一整天都很开心。`; the ledger remained at one request and 348 tokens afterward.
- Highlight coordinate conversion, 2x pixel alignment, invalid bounds and separate wrapped-line geometry checks pass. Removed fixed outer padding and highlight scaling; available numeric glyph bounds are grouped per line. Popup reveal uses a spring around the arrow tip with a separate short fade. Real cross-app alignment and subjective equivalence to macOS Look Up still need hands-on verification: computer-use attempts could not reliably retain/inspect the transient lookup window (`noWindowsAvailable` / `cgWindowNotFound`), and are not recorded as successful Safari visual acceptance.
- Release build, installed signature, existing dictionary/OCR/context/pressure checks and diff checks pass. Existing shortcut behavior is retained as requested. No screenshots, query content, endpoint URLs or credentials are added to the usage database or Git.

### 2026-11-04 · Glyph-preserving highlight (0.5.1)

- Replaced translucent paint over text with a local crop-derived yellow overlay: transparent solid strokes, color-matted antialiasing, tight ink bounds, subdued dark-background tint. Failed/unauthorized capture uses an unfilled outline. Capture is one-shot, bounded, cancellable and independent of OCR; privacy notes and an Appearance switch describe it.
- Raster checks pass for Chinese/Latin, light/dark backgrounds, blue glyphs, 14/30 pt text, 1×/2× scale, negative screen origins, blank rejection, bounds trimming and unchanged solid-glyph colors after compositing. Generated fixtures were visually inspected; the initial white edge halo was corrected. These checks validate rendering, not every application's AX geometry or physical Force Click.
- Release build and existing core, OCR, dictionary, AI-first pipeline and usage checks pass. No provider calls were made for this change.
- Installed 0.5.1 with the existing signing identity; signature verified and Clear Text Highlight visibly enabled in Appearance. A delayed Safari pointer test reported iPhone Mirroring as the foreground application, so it is not counted as successful Safari visual acceptance. Online service was temporarily disabled for the test and restored afterward.

### 2026-11-04 · Continuous expansion and forgiving targets (0.5.2)

- Inspected the supplied 12.115-second recording, including sampled frames around expansion: the title briefly moved to the upper edge and the explanation faded before returning. Code had a fixed SwiftUI root height, a separate 180 ms transition and a delayed 220 ms window animation. Replaced them with one display-link update of window geometry and clipped content reveal; disabled implicit material/mask animations and removed scrollbar layout reservations.
- Motion checks pass: monotonic reveal from rest, equivalent results at 60/120 Hz, preservation of position/velocity on reversal, convergence and immediate stop. Existing glyph, OCR, dictionary, usage and AI-first pipeline checks pass. Release 0.5.2 builds and the installed signature verifies.
- In the installed local preset popup, verified compact → expanded → context expanded → compact, with unchanged title/meaning positions in captured states. Verified coordinate clicks in the clear padding to the right of Explain, at the far right of the Context row, and outside the Close glyph all activate their intended controls. Hidden context is absent from the collapsed accessibility tree. These checks cover the installed preview and motion solver; they are not a new high-frame-rate recording of every intermediate frame or a full cross-app compatibility pass.
- No online requests were made. Test media, extracted user-video frames and personal configuration are not committed.
