# 界面本地化

CC FLOW 使用随应用打包的 `en.lproj/Localizable.strings` 和 `zh-Hans.lproj/Localizable.strings`。两份资源使用同一组稳定 key；`InfoPlist.strings` 继续使用 Apple 规定的系统 key。

## Key 约定

使用 `模块.语义`，例如 `settings.language`、`common.cancel`、`calendar.title`。key 使用小写字母、数字和下划线，层级用点分隔。修改中文或英文文案时只修改 value，不重命名 key。公共动作使用 `common`，功能专用文案归入 `settings`、`translation`、`session` 等模块。资源仍采用系统标准单表加载，无需网络请求或按页面下载。

```swift
Text("settings.language")
Text(appLocalized: item.titleKey)
let title = AppLocalization.string("settings.language")
let message = AppLocalization.format("settings.click_to_sign_in_to", platformName)
```

SwiftUI 字面量和 `Text(appLocalized:)` 从环境中的 locale 读取翻译。普通字符串通过 `AppLocalization.string/format` 读取；非主线程的错误描述等使用 `runtimeString/runtimeFormat`。格式占位符写在两种语言的 value 中，不写在 key 中；数量和用户输入作为参数传入。

## 语言选择

用户显式选择优先于系统首选语言；中文地区变体统一使用简体中文资源，不支持的语言回退英文。标识归一化集中在 `AppLanguage.resourceLanguageCode(for:)`，SwiftUI 和显式 Bundle 查找共用该规则。此原生应用没有账户语言或前后端语言协商。

## 数据与文案

协议标识、枚举 rawValue、用户输入、快捷回复正文和解析规则不作为翻译 key。需要显示的枚举使用独立 `titleKey`；内置快捷回复名称按稳定规则 ID 获取显示文案，用户修改后的名称原样显示。不要将已翻译字符串缓存成静态常量；静态配置保存 key，在显示时翻译。用户内容使用 `Text(verbatim:)`，不要再次查表。

## 验证

```sh
python3 scripts/check-localizations.py
python3 -m unittest discover -s scripts -p test_check_localizations.py
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests/AppLanguageTests
```

检查覆盖稳定 key 格式、重复 key、中英文 key 集合、两种译文的格式占位符、已知命名空间中未定义的引用，以及直接本地化入口中的中文 key。静态扫描不能推断所有动态字符串的来源；动态标题仍需通过单元测试和调用点审查验证。`DATA_IDENTIFIERS` 仅列出与本地化命名空间重叠的协议/SF Symbol/视图标识，不允许它们被用作显示 key。
