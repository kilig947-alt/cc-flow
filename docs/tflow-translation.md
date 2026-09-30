# Tflow 翻译

左侧功能内置「Tflow 翻译」，升级时追加，不改变既有功能排序或选择。设置 → 左侧功能 → Tflow 翻译 → 翻译服务，可配置服务。展开翻译面板后，右上角也提供服务设置入口。服务设置直接替换灵动岛左侧内容，左上角「返回」回到翻译，不打开独立窗口或弹出 sheet；原文和译文保持不变。

- Option-D：先通过 Accessibility 读取当前焦点元素的选中文字；无可用选词时读取剪贴板文字，或对剪贴板图片使用当前 OCR 服务（默认本机识别）。
- Option-S：调用系统交互式选区截图，使用当前 OCR 服务，再在灵动岛左侧展示翻译。Escape 取消；临时截图处理后删除。
- Option-A：展开灵动岛左侧 Tflow 翻译并聚焦输入框。Command-Return 提交翻译，Return 换行。
- 可在设置 → 快捷键修改或禁用这三组快捷键。关闭左侧 Tflow 功能时不注册其快捷键。

默认启用智谱、硅基流动和 MyMemory；升级追加新服务时保留旧服务的启停、模型和密钥配置。智谱和硅基流动预设免费模型，但使用官方 API 仍需填写个人 API Key，不借用 Bob 等软件的专属免密钥通道。支持并行对比多个已启用服务的结果、自动检测源语言、自动中英互译、手动语言选择、复制完整译文、系统朗读。翻译统一在灵动岛左侧展示，固定展开复用灵动岛原有控制。原文改变后旧请求失效，避免慢请求覆盖新内容。图片默认本机识别；在 OCR 设置中明确选择云服务后，只上传给该服务。不会在后台监听剪贴板。

## 设置和结果交互

设置在灵动岛内分为「翻译服务」「复制结果」「系统语音」「OCR」，左上角返回翻译页。服务列表直接切换启用状态，密钥、地址、模型和提示词编辑后保存。

- 每条结果的折叠按钮右侧有设置菜单，可为该服务保存「默认展开 · 自动翻译」或「默认折叠 · 展开时翻译」。默认折叠不会发起请求（也不读取密钥），手动展开才请求；已有译文折叠再展开不重复请求。折叠正在请求的服务会取消本地请求，并丢弃其迟到响应。重新提交原文或改变语言会使旧结果失效。
- 英文译文可分别开启小驼峰、大驼峰、下划线、短横线、常量命名复制按钮；普通复制始终保留完整文本。格式开关自动保存，非英文结果不展示命名格式按钮。复制成功显示绿色勾选，约 1.5 秒后恢复。
- 默认使用 macOS 系统语音，可关闭朗读、选择已安装声音、调整语速并试听。自动声音按文本语言匹配；播放时显示动态波形和停止提示，再次点击停止，结束或取消时恢复。切换朗读目标会停止上一个目标；离开播放控件也会停止，避免折叠后继续播报。

## 服务与免费条件

“免费”包括有限免费额度或新用户试用，不能承诺所有服务永久免密钥免费。地域可用性、账号资格和额度以各服务方当前政策为准。

| 服务 | 接入配置 | 免费条件 |
| --- | --- | --- |
| 智谱 | 智谱 API Key，预设 `glm-4-flash-250414` | Flash 免费模型，受账号权限与频率限制 |
| 硅基流动 | 硅基流动 API Key，预设 `tencent/Hunyuan-MT-7B` | 官网标价免费，受账号权限与频率限制 |
| MyMemory | 无需密钥 | 公共接口，有每日限额，单次最多 500 UTF-8 字节 |
| 百度翻译 | APP ID + 应用密钥 | 按账号资格提供免费额度；超额可能计费 |
| 有道翻译 | 应用 ID + 应用密钥 | 新用户体验金，用尽后按量计费 |
| Microsoft Translator | Azure Key + 资源区域 | 选择 F0 免费资源；其他付费套餐可能计费 |
| DeepL API Free | API Free Key | 需可注册地区的 API Free 账号，存在月额度 |
| AI 翻译（额外） | Base URL、Path、模型、可选 Key、提示词 | OpenAI 兼容 Chat Completions；按用户服务商计费，本地服务可无密钥 |

AI 默认 Base URL 为 `https://api.openai.com`，Path 为 `/v1/chat/completions`。Base URL 的路径与 API Path 会拼接，请勿重复填写 `/v1`。支持 HTTPS，以及 `localhost` / `127.0.0.1` 的本地 HTTP 服务。提示词支持 `{source}` / `{target}`。密钥单独写入 macOS Keychain；普通配置保存在 UserDefaults，不记录原文、译文历史或密钥日志。

## 权限和边界

选词使用辅助功能权限；不提供 Accessibility 选词属性的应用，需先复制再按 Option-D。截图需要屏幕录制权限。两项权限均按用户动作请求，不在启动时弹窗。截图或 OCR 取消不会使用上一次图片。目标自动选择规则为：中文 → 英语，其他语言 → 简体中文。识别和翻译失败在面板内提示，不自动换服务上传文本。

本次不含收藏、历史记录或插件市场。系统词典查询使用 macOS 已安装的词典（需在词典 App 中启用英汉词典），不捆绑 Bob 的词库。每个平台有一个独立配置，自定义 AI 另有一个独立配置。

## 参考

- [硅基流动模型价格](https://siliconflow.cn/pricing) · [接入指南](https://docs.siliconflow.cn/docs/userguide/quickstart)
- [智谱 Flash 模型](https://docs.bigmodel.cn/cn/guide/models/free/glm-4-flash-250414)
- [Bob 使用指南](https://bobtranslate.com/guide/)
- [MyMemory API](https://mymemory.translated.net/doc/spec.php)
- [百度翻译 API](https://fanyi-api.baidu.com/doc/21)
- [有道文本翻译 API](https://ai.youdao.com/DOCSIRMA/html/trans/api/wbfy/index.html) · [价格和试用](https://ai.youdao.com/product-fanyi-text.s)
- [Microsoft Translate API](https://learn.microsoft.com/en-us/azure/ai-services/translator/text-translation/reference/v3/translate)
- [DeepL 官方 OpenAPI](https://github.com/DeepLcom/openapi)

## 验证

`xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests/TranslationTests -only-testing:CCFlowTests/GlobalShortcutTests`

另已运行 5 项快捷键设置持久化测试。首轮扩大到整个 `AppSettingsPersistenceTests` 时，`testMascotOverridesLegacyDictionaryMigratesToDataStorage` 和 `testPreviewMascotKindPersists` 两项宠物配置测试失败，未修改其逻辑。

人工验收：在支持辅助功能的文本编辑器中选中文字按 Option-D；无选词时分别复制文字和图片重试；Option-S 框选文字并测试 Escape 取消；Option-A 后直接输入并按 Command-Return；修改快捷键再验证；配置服务后验证其真实账号额度和鉴权错误提示。

## 扩展服务目录（2026-09-30）

目录将已启用服务置顶，其余按通用翻译、AI 模型、本地服务分组，支持搜索和仅显示已启用。新增服务默认关闭；智谱、硅基流动、MyMemory 的默认启用与已保存偏好保持不变。每个文本服务沿用独立的默认展开设置。设置均在灵动岛内，无新增窗口。

- 通用翻译：百度、有道、Microsoft、DeepL API Free、MyMemory、火山、阿里、彩云、小牛、Google、Amazon、腾讯翻译君（TokenHub `hy-mt2-plus`）。火山使用 V4 HMAC-SHA256；Amazon 使用 SigV4；阿里使用 RPC HMAC-SHA1。永久 Access Key/Secret Key 配置，不支持临时 STS token。
- AI：智谱、硅基流动、AiHubMix、SophNet、302AI、OpenAI、Azure OpenAI、Gemini、Claude、Grok、Groq、OpenRouter、DeepSeek、千问、文心、豆包、混元、模力方舟、Kimi、零一万物、自定义兼容接口。Claude 使用原生 Messages 格式；Azure 使用 v1 `api-key` 鉴权；Gemini 使用官方兼容接口。其他平台使用各自的兼容接口。模型未预置的平台需填写自己已开通的模型 ID；Azure 填部署名称，豆包可填接入点 ID。地域专属地址可编辑。
- 本地：Ollama、LM Studio（先启动服务并加载模型），以及 macOS 系统词典查询。
- OCR：系统 Vision（默认）、火山 OCRNormal、腾讯 GeneralBasicOCR、腾讯 ImageTranslateLLM、百度 general_basic、有道通用 OCR、Google Vision DOCUMENT_TEXT_DETECTION。截图与剪贴板使用同一选项。云端上传前统一转换 PNG，限制 4 MB / 4000 万像素（有道另限制边长 11–2047 px、Base64 编码后小于 2 MB）；无隐式切换服务。密钥以 `ocr.<provider>` 独立存入 Keychain。
- 腾讯图片翻译一次返回原文与译文，不会再自动请求其他翻译服务；仍可手动点击「翻译」对比文本服务。目标自动时此图片接口默认中文，可先选择英语等明确目标语言。

### 适配依据

- [腾讯旧接口迁移说明](https://cloud.tencent.com/document/product/551/104415) · [TokenHub 翻译模型](https://cloud.tencent.com/document/product/1823/132252)
- [腾讯图片翻译](https://cloud.tencent.com/document/product/551/118482)
- [火山翻译](https://docs.volcengine.com/docs/MachineTranslation/TextTranslationAPI) · [火山 OCR](https://www.volcengine.com/docs/86081/1660261)
- [彩云](https://docs.caiyunapp.com/lingocloud-api/) · [小牛](https://niutrans.com/documents/contents/trans_detection)
- [Amazon Translate](https://docs.aws.amazon.com/translate/latest/APIReference/API_TranslateText.html)
- [Claude Messages](https://platform.claude.com/docs/en/api/messages/create) · [Azure v1](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/api-version-lifecycle) · [Gemini 兼容接口](https://ai.google.dev/gemini-api/docs/openai)
- [模力方舟](https://moark.com/docs/integrations/intro) · [SophNet](https://sophnet.com/docs/component/API.html)
- [有道 OCR](https://ai.youdao.com/DOCSIRMA/html/ocr/api/tyocr/index.html) · [Google OCR](https://cloud.google.com/vision/docs/ocr) · [百度 OCR 官方 SDK](https://github.com/Baidu-AIP/python-sdk/blob/master/aip/ocr.py)

验证包含请求路由、凭据头、原文与提示词分离、响应夹具、云端业务错误、配置迁移及折叠懒加载。没有平台账号密钥，未声称完成各收费接口的线上联调；模型开通和地区可用性需用真实账号验收。


### 选词与服务目录交互修正

- 服务列表使用明确的「启用 / 停用」操作，结果展示方式改为分段选项。切换服务启用状态时同时选中、展示配置详情，并滚动到移动后的条目；清除搜索条件，停用时退出仅启用筛选。
- 选词优先读取 AXSelectedText。浏览器未暴露此属性时，在激活灵动岛之前向原应用发送 Command-C，等待剪贴板变化后读取新选区，并恢复原有剪贴板各类型数据。未复制到选区才使用原剪贴板。无辅助功能权限时明确提示，不将权限失败当成没有选词；右上角剪贴板按钮可直接翻译已复制内容。
