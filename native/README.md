# PressTrans 原生预览版

Swift + AppKit + SwiftUI 菜单栏应用，支持英汉离线查词、可选 DeepSeek 语境增强，以及辅助功能选区读取。无需 Node 服务即可运行。当前构建仅验证 Apple Silicon macOS；最低部署版本为 macOS 14，Intel 构建及 8 GB 机器尚未验收。

## 构建与运行

```sh
bash scripts/build-native.sh
```

输出 `native/build/PressTrans.app`。首次构建下载固定版本 ECDICT（66 MB），校验 SHA-256，然后建立约 90.2 MB 的只读 SQLite 词库。完整应用约 91 MB，之后离线查询不联网。词库二进制和构建产物不进入 Git；可由源校验文件重建。需要 Python 3 和 Swift 工具链，本机 Command Line Tools 已可构建，无第三方 Swift 依赖。

打开应用后，可从“手动查询”直接试用离线词典。跨应用查询需用户在系统设置 → 隐私与安全性 → 辅助功能中允许 PressTrans，随后在其他应用选中文字并按 Option+Shift+T。设置页自动检测权限；若系统开关已开但应用仍报告未授权，应移除旧签名条目，重新添加 `/Applications/PressTrans.app`。取词不设应用白名单，按可访问性接口能力适配；兼容范围以真实验收记录为准。

构建脚本使用项目专用钥匙串中的固定本地开发证书，原始密钥与证书封装不会上传 Git。不添加系统信任，不用每次变化的 ad-hoc 身份。`native/.signing/` 必须保留且禁止提交；删除后重建身份会导致重新授权。正式对外分发仍需 Developer ID 签名和公证。

固定安装路径为 `/Applications/PressTrans.app`。设置打开时临时显示 Dock 图标，关闭后回到菜单栏模式。菜单栏可以隐藏，重新从启动台/Finder 打开应用即可回到设置。应用已包含原生 ICNS 图标。

## 查询行为

- 默认离线，不要求账户、Base URL 或 API Key。
- 顺序为精确词条、已知词形、词形组合后的短语、可分离短语、最长词组和单词、有限拼写建议。
- 规范化大小写、空白、部分标点和弯引号；复数、过去式、进行时等结合词库词形与规则处理。
- `took off` → `take off`；`turned it down` → `turn down`；`looked after` → `look after`；`recieve` 显示 `receive` 拼写建议。实际匹配词条可见。
- 最多分析前 24 个词、展示 5 个条目；单条释义展示上限 1800 字符。复杂句回退到部分词组/单词释义，明确标注不是整句翻译。
- 离线词典不承诺语境消歧，不能可靠理解讽刺、梗或未收录习语。模板仅排版已有释义，不生成新的翻译结论。
- 可选在线增强需主动开启；个人 DeepSeek 配置位于“隐私与服务”。官方地址固定，不要求填写 Base URL。离线结果先显示，在线成功后替换；认证失败、限流、断流或超时恢复完整离线结果。
- 个人 API 配置只是开发/高级入口。面向普通用户的免配置云服务尚未建设，未来需要自有后端、账户/额度与成本控制；不得将任何测试密钥写入客户端分发。

## 隐私与资源管理

按用户要求，供应商密钥改存 `~/Library/Application Support/PressTrans/provider.json`，目录权限 0700、文件 0600，先写同目录临时文件再原子替换。应用不再调用系统钥匙串接口，不会出现读取钥匙串密码的弹窗；遗留钥匙串项不自动读取或删除。该配置是本机明文配置，不能作为公共分发密钥使用。安装包不包含配置文件或 `.env` 路径。线上请求仍使用官方 HTTPS 地址；仅主动查询且开启增强时发送选区及附近上下文。没有词典遥测、正文持久化或后台扫描。

AX 首先请求有限长度的周边文本，仅对字符数已知且不超过 12000 的控件回退读取完整值；拒绝安全输入框。未读到上下文时明确标记，不通过剪贴板静默补取。复制操作只在点击“复制”时写入剪贴板。

词库由 actor 串行管理，只读 SQLite，页面缓存 2 MB、关闭 mmap，无整库内存加载。短语候选数最多 96，拼写候选最多 160。任务关闭时取消，旧任务结果由 generation 隔离；流式 UI 更新节流 40 ms，请求采用临时 URLSession，结束后释放。没有常驻生成模型或轮询计时器。原生浮窗支持外部点击、滚动、Esc、切换应用关闭；动画尊重“减少动态效果”。

## 验证

```sh
bash scripts/build-native.sh
PRESSTRANS_DICTIONARY="$PWD/native/Resources/dictionary.sqlite" native/.build/release/PressTransChecks
```

核心可执行检查覆盖上下文预算、段落层级、SSE 分帧、真实词库词形/短语/拼写、未知词、长输入，以及无在线服务、半截回答失败回退、完整在线回答和取消。上游在管线测试中模拟，不消耗用户密钥额度。

2026-11-03，在 M5 / 24 GB / macOS 27.2 上：词库 769032 条，90210304 字节（以生成 metadata 为准）；离线测试多数样本低于 5 ms，长输入约 12–22 ms。独立词典测试进程峰值 RSS 7.8 MB；原生 UI 打开查词浮窗后的一个采样 RSS 126 MiB、空闲 CPU 0.0%。这些是开发机采样，不能证明长期无增长或 8 GB Intel 机器性能。

另做了 macOS NaturalLanguage 的独立候选评估：词形/词性分析首次约 43 ms，重复短句 p50 0.059 ms，进程峰值 RSS 18.6 MB；完整冷进程含启动约 2.4 秒。它可辅助检索，不是生成译文模型，尚未接入正式查询路径。第一版先用现有词形表与规则，以减少首次加载和常驻开销。

## 后续全局适配

1. 完成辅助功能授权后的 TextEdit、Safari、Chrome、PDF 和编辑器兼容矩阵，验证选区与周边文本是否一致。
2. 为网页增加 Safari Web Extension 适配器，将选区、句子、段落、链接上下文交给原生应用；完整 Xcode、扩展签名与安装验证待补齐。
3. 直接读取失败时，可选本地 Vision OCR 回退（macOS 15.2+，需屏幕录制授权）；其余情况明确降级为手动输入。
4. 实验重按的物理手势、压力阈值和各应用命中单词须继续真机验收；不把检测逻辑的单元检查当成真实重按成功。
5. 开展 8 GB Intel CPU 真机、冷启动、休眠唤醒、多屏全屏及长时间开关浮窗的资源测试。

## 词库来源

[ECDICT](https://github.com/skywind3000/ECDICT)，固定提交 `39cfb9672c0906b63569e0453c2e6abfb9ab182a`。保留原始 MIT 许可于 `Resources/ECDICT-LICENSE.txt` 并随应用打包。作者在 [Issue 134](https://github.com/skywind3000/ECDICT/issues/134) 确认可在商业应用中提供离线查词；请以该 issue 实际内容为准。构建源哈希在 `scripts/dictionary-source.json`，生成元数据在 `Resources/dictionary-info.json`。

## 实验重按与可逆切换

设置提供“系统查词 / PressTrans”分段按钮。启用顺序：权限有效 → 压力监听启动成功 → 持久保存原始系统查词偏好 → 关闭系统查词，任一步失败都不进入开启状态。关闭和正常退出会停止监听并恢复原始值（包括原先不存在的键）；中途崩溃时，恢复记录留存，下次启动恢复。若用户随后手动修改了系统设置，避免覆盖其新选择。强制结束进程后系统偏好不能立即恢复，可重新打开应用或在触控板设置中手动恢复。

只触及三项已观察到的查词偏好：全局 `com.apple.trackpad.forceClick`、内置及蓝牙触控板的 `TrackpadThreeFingerTapGesture`，不修改 `ForceSuppressed` 等触感开关。不保证未来系统沿用这些未公开配置；需核对系统设置与真实行为。

压力通过系统私有 MultitouchSupport 框架的动态符号读取，这是实验性适配，不可宣称为 App Store 可上架方案。接口不存在时不开启监听。单指压力超过阈值，且在单次按下后的短时间内、指针未拖动，才发出一次查询；普通点击、双击、拖动和长按有过滤。只在启用时监听，压力回调不保存原始触点。指针查询使用公开 AX 命中与范围 API，应用不提供相关接口时会提示不支持，不模拟点击、不偷偷复制。

## 全局取词、OCR 与界面更新

设置改为原生侧栏与分组表单：通用、翻译、重按与快捷键、隐私与服务、手动查询。窗口可调整大小，支持 Command-W；只在设置窗口可见时显示 Dock。浮窗采用 AppKit popover 材质、指向目标的箭头与黄色点击穿透高亮，支持减少动态效果。

直接取词按能力路由，不按应用包名限制：首先尝试 WebKit/Chromium 常见的 AX 文本标记接口，再尝试字符范围接口；从命中或焦点节点沿父链有限查找，绝不遍历整个文档。标记范围先读取长度，目标最多 2000 UTF-16 单元，上下文最多 3000，再经公共预算限制；指针查询必须命中真实字词边界，空白不能吸附到附近单词。最终选区仍限制为 1000 Unicode 码点。浏览器标记接口并非所有应用都支持，需保留回退。

Option-Shift-P 查询指针下的词，与重按共用路径；Option-Shift-T 处理已有选区。“重按与快捷键 → 兼容性说明”提供一次性的 5 秒延时取词检测，并在内存中显示最近一次结果摘要，退出即清除。这不是物理压力测试。

可选“取词失败时使用屏幕识字”默认关闭。仅主动指针查询且 AX 读取失败时，ScreenCaptureKit 截取指针附近至多 640×260 点的可见区域；Vision 在本机识别，选择包围指针的字词，附近上下文只使用同一识别行。图片不落盘、不上传，不创建持续录制流。拒绝安全输入框，不使用 OCR 绕过权限拒绝。开启在线释义时，识别出的目标和目标行仍会按在线设置发送给 DeepSeek。OCR 不能保证所有语言、低清文字、竖排或复杂排版正确。

在线释义支持外语→中文；中文默认先给英语译文再用中文解释，可选择其他目标语言或仅中文释义。代码/符号优先解释实际作用。当前 DeepSeek 官方 deepseek-flash 支持图片输入（见官方 Vision 文档），本版选择本地 OCR + 文本释义，不发送屏幕图片。

## Languages and online services (0.3)

App UI: English, Simplified Chinese, Traditional Chinese, or system default. Translation and explanation languages are independent, with automatic source detection and custom language names. The bundled offline dictionary remains English → Simplified Chinese only.

Online service defaults to DeepSeek and accepts editable OpenAI Chat Completions compatible Base URLs and model IDs. See [API setup guide](../docs/API-setup.md) for provider presets, language settings, data handling and troubleshooting. Keys are bound to the saved endpoint; redirects are rejected. Presets are not a claim of live paid-account validation.
