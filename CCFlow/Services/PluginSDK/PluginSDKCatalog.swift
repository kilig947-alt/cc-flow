import Foundation

struct PluginSDKSchema: Decodable {
    struct Method: Decodable {
        let name: String
        let summary: String
        let capability: String?
        let risk: String
        let params: [String: String]
        let returns: String
    }
    let schemaVersion: Int
    let sdkVersion: String
    let moduleURL: String
    let methods: [Method]
}

enum PluginSDKCatalog {
    static let schema: PluginSDKSchema = {
        let url = Bundle.main.url(forResource: "cc-flow-api.schema", withExtension: "json", subdirectory: "PluginSDK")
            ?? Bundle.main.url(forResource: "cc-flow-api.schema", withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let schema = try? JSONDecoder().decode(PluginSDKSchema.self, from: data) else {
            assertionFailure("Missing or invalid CC FLOW Plugin SDK schema")
            return PluginSDKSchema(schemaVersion: 1, sdkVersion: "1.0.0", moduleURL: "cc-flow-sdk://v1/index.js", methods: [])
        }
        return schema
    }()

    static var publicAPIDocumentation: String {
        let namespaces = Set(schema.methods.compactMap { $0.name.split(separator: ".").first.map(String.init) }).sorted()
        var lines = [
            "【CC FLOW Plugin SDK \(schema.sdkVersion)】",
            "在 <script type=\"module\"> 中按需导入：",
            "import { \(namespaces.joined(separator: ", ")) } from \"\(schema.moduleURL)\";",
            "",
            "所有方法返回 Promise。普通浏览器中 Bridge 不存在，必须用 try/catch 安全降级。",
            "仅可调用 manifest capabilities 已声明并经用户授权的方法。",
            ""
        ]
        for method in schema.methods {
            let capability = method.capability.map { " capability: \($0);" } ?? ""
            let params = method.params.isEmpty ? "{}" : method.params.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")
            lines.append("- \(method.name)({ \(params) }) → \(method.returns)")
            lines.append("  \(method.summary) [risk: \(method.risk);\(capability)]")
        }
        return lines.joined(separator: "\n")
    }
}

enum GeneratedPanelPrompt {
    static var text: String {
        """
        我想创建一个 CC FLOW 左侧插件面板。请先询问我希望面板实现什么需求，再根据回答直接生成并保存文件。

        【输出目录】
        为插件选择稳定、安全的反向域名 ID，并创建目录：
        ~/Library/Application Support/cc-flow/custom-areas/[插件ID]/

        必须生成 index.html 和 cc-flow-panel.json：
        {
          "manifestVersion": 2,
          "id": "com.example.plugin",
          "name": "插件显示名称",
          "version": "1.0.0",
          "entryPoint": "index.html",
          "icon": "sparkles",
          "sdkVersion": "^1.0",
          "capabilities": ["island.presentation"],
          "allowsNetworkAccess": false
        }

        只声明实际使用的 capabilities。只有确实需要外部 HTTP/HTTPS 时才启用网络。不要修改 CC FLOW 源码或 custom-areas.json。

        【页面要求】
        - 使用 WKWebView 可直接加载的 HTML、CSS 和 JavaScript。
        - 同时适配浅色/深色外观与可调整面板尺寸。
        - 不得调用未列出的 Bridge、Mineradio 内部 API、Shell、AppleScript 或任意路径文件 API。
        - Bridge 不存在或用户拒绝权限时必须安全降级。

        \(PluginSDKCatalog.publicAPIDocumentation)

        完成后检查入口和 manifest 已写入目标目录，并告诉我返回 CC FLOW。CC FLOW 会自动扫描插件。
        """
    }
}
