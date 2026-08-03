import Foundation
import Testing
@testable import CC_FLOW

@Suite("Plugin SDK")
@MainActor
struct PluginSDKTests {
    @Test("schema methods are unique and documented")
    func schemaIntegrity() {
        let schema = PluginSDKCatalog.schema
        #expect(schema.schemaVersion == 1)
        #expect(schema.sdkVersion == "1.0.0")
        #expect(Set(schema.methods.map(\.name)).count == schema.methods.count)
        #expect(schema.methods.allSatisfy { !$0.summary.isEmpty && !$0.risk.isEmpty && !$0.returns.isEmpty })
    }

    @Test("generated prompt imports the module and derives API documentation")
    func generatedPrompt() {
        let prompt = GeneratedPanelPrompt.text
        #expect(prompt.contains("cc-flow-sdk://v1/index.js"))
        #expect(prompt.contains("system.getMetrics"))
        #expect(prompt.contains("sessions.status.read"))
        #expect(!prompt.contains("window.receiveMetrics"))
    }

    @Test("v2 manifest decodes capabilities")
    func manifestDecode() throws {
        let data = Data(#"{"manifestVersion":2,"id":"com.example.panel","name":"Panel","version":"1.0.0","entryPoint":"index.html","sdkVersion":"^1.0","capabilities":["system.metrics.read"]}"#.utf8)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        #expect(manifest.id == "com.example.panel")
        #expect(manifest.capabilities == ["system.metrics.read"])
    }

    @Test("run-scoped sensitive grants match only the same plugin capability")
    func runScopedSensitiveGrant() throws {
        let data = Data(#"{"manifestVersion":2,"id":"com.example.panel","name":"Panel","version":"1.0.0","entryPoint":"index.html","sdkVersion":"^1.0","capabilities":["clipboard.write","apps.open"]}"#.utf8)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        PluginSensitiveCapabilityGrantStore.resetForTesting()

        #expect(!PluginSensitiveCapabilityGrantStore.isGranted(
            "clipboard.write",
            areaID: "area-a",
            manifest: manifest
        ))

        PluginSensitiveCapabilityGrantStore.grant(
            "clipboard.write",
            areaID: "area-a",
            manifest: manifest
        )

        #expect(PluginSensitiveCapabilityGrantStore.isGranted(
            "clipboard.write",
            areaID: "area-a",
            manifest: manifest
        ))
        #expect(!PluginSensitiveCapabilityGrantStore.isGranted(
            "apps.open",
            areaID: "area-a",
            manifest: manifest
        ))
        #expect(!PluginSensitiveCapabilityGrantStore.isGranted(
            "clipboard.write",
            areaID: "area-b",
            manifest: manifest
        ))

        PluginSensitiveCapabilityGrantStore.resetForTesting()
        #expect(!PluginSensitiveCapabilityGrantStore.isGranted(
            "clipboard.write",
            areaID: "area-a",
            manifest: manifest
        ))
    }
}
