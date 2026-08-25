import AppKit
import Carbon.HIToolbox
import Combine

extension Notification.Name {
    static let ccFlowOpenActiveSessionShortcut = Notification.Name("ccFlowOpenActiveSessionShortcut")
    static let ccFlowOpenSessionListShortcut = Notification.Name("ccFlowOpenSessionListShortcut")
    static let ccFlowOpenRecentLeftFeatureShortcut = Notification.Name("ccFlowOpenRecentLeftFeatureShortcut")
    static let ccFlowOpenLeftFeatureShortcut = Notification.Name("ccFlowOpenLeftFeatureShortcut")
    static let ccFlowPresentNotchDetachmentHint = Notification.Name("ccFlowPresentNotchDetachmentHint")
    static let ccFlowGiflowSelectionCaptureShortcut = Notification.Name("ccFlowGiflowSelectionCaptureShortcut")
    static let ccFlowGiflowFullScreenCaptureShortcut = Notification.Name("ccFlowGiflowFullScreenCaptureShortcut")
    static let ccFlowGiflowOpenRecordingsShortcut = Notification.Name("ccFlowGiflowOpenRecordingsShortcut")
    static let ccFlowCollapseIsland = Notification.Name("ccFlowCollapseIsland")
}

@MainActor
final class GlobalShortcutManager: ObservableObject {
    static let shared = GlobalShortcutManager()

    private enum Target: Hashable {
        case action(GlobalShortcutAction)
        case leftFeature(String)
    }

    private var hotKeyRefs: [Target: EventHotKeyRef] = [:]
    private var registeredTargetsByHotKeyID: [UInt32: Target] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var cancellables = Set<AnyCancellable>()
    private let signature = GlobalShortcutManager.fourCharCode(from: "PISL")
    private var nextHotKeyID: UInt32 = 100
    @Published private(set) var registrationErrors: [String: String] = [:]

    private init() {
        installEventHandlerIfNeeded()

        Publishers.MergeMany(
            AppSettings.shared.$openActiveSessionShortcut.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$openLeftFeatureShortcut.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$openSessionListShortcut.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$giflowSelectionCaptureShortcut.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$giflowFullScreenCaptureShortcut.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$giflowOpenRecordingsShortcut.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] _ in
            self?.refreshRegistrations()
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .ccFlowLeftFeaturesChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshRegistrations() }
            .store(in: &cancellables)
    }

    func start() {
        refreshRegistrations()
    }

    private func refreshRegistrations() {
        unregisterAllHotKeys()
        registrationErrors = [:]

        var registeredShortcuts = Set<GlobalShortcut>()

        for action in GlobalShortcutAction.allCases {
            guard let shortcut = AppSettings.shortcut(for: action) else { continue }
            guard registeredShortcuts.insert(shortcut).inserted else {
                registrationErrors["action:\(action.rawValue)"] = "与另一个已配置快捷键冲突"
                continue
            }

            register(shortcut, for: .action(action))
        }

        for feature in LeftFeatureStore.shared.enabledFeatures {
            guard let shortcut = feature.globalShortcut else { continue }
            guard registeredShortcuts.insert(shortcut).inserted else {
                registrationErrors["feature:\(feature.id)"] = "与另一个已配置快捷键冲突"
                continue
            }
            register(shortcut, for: .leftFeature(feature.id))
        }
    }

    private func register(_ shortcut: GlobalShortcut, for target: Target) {
        var hotKeyRef: EventHotKeyRef?
        let carbonID = nextRegistrationID()
        let hotKeyID = EventHotKeyID(signature: signature, id: carbonID)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            let key: String
            switch target {
            case .action(let action): key = "action:\(action.rawValue)"
            case .leftFeature(let id): key = "feature:\(id)"
            }
            registrationErrors[key] = "系统注册失败（\(status)），请检查是否被其他应用占用"
            return
        }
        hotKeyRefs[target] = hotKeyRef
        registeredTargetsByHotKeyID[carbonID] = target
    }

    func registrationError(forFeatureID id: String) -> String? {
        registrationErrors["feature:\(id)"]
    }

    func registrationError(for action: GlobalShortcutAction) -> String? {
        registrationErrors["action:\(action.rawValue)"]
    }

    private func unregisterAllHotKeys() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        registeredTargetsByHotKeyID.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyEvent(event)
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }

        guard let target = registeredTargetsByHotKeyID[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        switch target {
        case .action(let action):
            switch action {
            case .openActiveSession:
                NotificationCenter.default.post(name: .ccFlowOpenActiveSessionShortcut, object: nil)
            case .openLeftFeature:
                NotificationCenter.default.post(name: .ccFlowOpenRecentLeftFeatureShortcut, object: nil)
            case .openSessionList:
                NotificationCenter.default.post(name: .ccFlowOpenSessionListShortcut, object: nil)
            case .giflowSelectionCapture:
                GiflowStore.shared.triggerSelectionCapture()
            case .giflowFullScreenCapture:
                GiflowStore.shared.triggerFullScreenCapture()
            case .giflowOpenRecordings:
                GiflowStore.shared.openRecordingsList()
            }
        case .leftFeature(let featureID):
            NotificationCenter.default.post(
                name: .ccFlowOpenLeftFeatureShortcut,
                object: nil,
                userInfo: ["featureID": featureID]
            )
        }

        return noErr
    }

    private func nextRegistrationID() -> UInt32 {
        defer {
            nextHotKeyID = nextHotKeyID == UInt32.max ? 100 : nextHotKeyID + 1
        }
        return nextHotKeyID
    }

    private static func fourCharCode(from string: String) -> OSType {
        string.utf8.prefix(4).reduce(0) { partial, character in
            (partial << 8) + OSType(character)
        }
    }
}
