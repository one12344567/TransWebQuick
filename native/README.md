# PressTrans 原生预览版

Swift + AppKit + SwiftUI 菜单栏应用，支持英汉离线查词、可选 DeepSeek 语境增强，以及辅助功能选区读取。无需 Node 服务即可运行。当前构建仅验证 Apple Silicon macOS；最低部署版本为 macOS 14，Intel 构建及 8 GB 机器尚未验收。

## 构建与运行

```sh
bash scripts/build-native.sh
```

输出 `native/build/PressTrans.app`。首次构建下载固定版本 ECDICT（66 MB），校验 SHA-256，然后建立约 90.2 MB 的只读 SQLite 词库。完整应用约 91 MB，之后离线查询不联网。词库二进制和构建产物不进入 Git；可由源校验文件重建。需要 Python 3 和 Swift 工具链，本机 Command Line Tools 已可构建，无第三方 Swift 依赖。

打开应用后，可直接点击“试试离线查词”。跨应用查询需用户在系统设置 → 隐私与安全性 → 辅助功能中允许 PressTrans，随后在其他应用选中文字并按 Option+Shift+T。辅助功能授权尚未在本机完成，多应用兼容性仍待实测。当前不是全局 Force Touch 接管器，也不会更改系统重按设置。

构建脚本使用临时签名；正式分发仍需开发者签名、公证与安装流程。更换构建签名后，系统可能要求重新授权辅助功能。

## 查询行为

- 默认离线，不要求账户、Base URL 或 API Key。
- 顺序为精确词条、已知词形、词形组合后的短语、可分离短语、最长词组和单词、有限拼写建议。
- 规范化大小写、空白、部分标点和弯引号；复数、过去式、进行时等结合词库词形与规则处理。
- `took off` → `take off`；`turned it down` → `turn down`；`looked after` → `look after`；`recieve` 显示 `receive` 拼写建议。实际匹配词条可见。
- 最多分析前 24 个词、展示 5 个条目；单条释义展示上限 1800 字符。复杂句回退到部分词组/单词释义，明确标注不是整句翻译。
- 离线词典不承诺语境消歧，不能可靠理解讽刺、梗或未收录习语。模板仅排版已有释义，不生成新的翻译结论。
- 可选在线增强需主动开启；个人 DeepSeek 配置位于高级设置。官方地址固定，不要求填写 Base URL。离线结果先显示，在线成功后替换；认证失败、限流、断流或超时恢复完整离线结果。
- 个人 API 配置只是开发/高级入口。面向普通用户的免配置云服务尚未建设，未来需要自有后端、账户/额度与成本控制；不得将任何测试密钥写入客户端分发。

## 隐私与资源管理

密钥保存在系统钥匙串。默认构建不含本地 `.env` 路径；仅开发者明确运行 `PRESSTRANS_DEV_CONFIG=1 bash scripts/build-native.sh` 才写入忽略文件的路径，始终不复制密钥。线上请求使用固定官方 HTTPS 地址；仅主动查询且开启增强时发送选区及附近上下文。没有词典遥测、正文持久化或后台扫描。

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
3. 对无法公开读取文本的应用，明确降级为手动输入。OCR 作为需主动授权的可选功能，当前没有实现。
4. 全局重按须单独验证公开 API 可行性；不将网页重按成功等同于系统全局可用，不依赖私有框架冒充已完成。
5. 开展 8 GB Intel CPU 真机、冷启动、休眠唤醒、多屏全屏及长时间开关浮窗的资源测试。

## 词库来源

[ECDICT](https://github.com/skywind3000/ECDICT)，固定提交 `39cfb9672c0906b63569e0453c2e6abfb9ab182a`。保留原始 MIT 许可于 `Resources/ECDICT-LICENSE.txt` 并随应用打包。作者在 [Issue 134](https://github.com/skywind3000/ECDICT/issues/134) 确认可在商业应用中提供离线查词；请以该 issue 实际内容为准。构建源哈希在 `scripts/dictionary-source.json`，生成元数据在 `Resources/dictionary-info.json`。
