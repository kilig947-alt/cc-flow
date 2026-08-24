//
//  EventMonitors.swift
//  CCFlow
//
//  Singleton that aggregates all event monitors
//

import AppKit
import Combine

@MainActor
final class EventMonitors {
    static let shared = EventMonitors()

    let mouseLocation = CurrentValueSubject<CGPoint, Never>(.zero)
    let mouseDown = PassthroughSubject<NSEvent, Never>()
    let mouseDragged = PassthroughSubject<NSEvent, Never>()
    let mouseUp = PassthroughSubject<NSEvent, Never>()
    let keyDown = PassthroughSubject<NSEvent, Never>()

    private var mouseMoveMonitor: EventMonitoring?
    private var mouseDownMonitor: EventMonitoring?
    private var mouseDraggedMonitor: EventMonitoring?
    private var mouseUpMonitor: EventMonitoring?
    private var keyDownMonitor: EventMonitoring?
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let currentMouseLocation: () -> CGPoint
    private let monitorFactory: (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> EventMonitoring
    private var monitoringLevel: EnergyEventMonitoringLevel = .full
    private var cancellables = Set<AnyCancellable>()

    convenience private init() {
        self.init(
            notificationCenter: .default,
            workspaceNotificationCenter: NSWorkspace.shared.notificationCenter,
            currentMouseLocation: { NSEvent.mouseLocation },
            monitorFactory: { mask, handler in
                EventMonitor(mask: mask, handler: handler)
            },
            energyPolicyPublisher: EnergyGovernor.shared.$policy.eraseToAnyPublisher()
        )
    }

    init(
        notificationCenter: NotificationCenter,
        workspaceNotificationCenter: NotificationCenter,
        currentMouseLocation: @escaping () -> CGPoint,
        monitorFactory: @escaping (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> EventMonitoring,
        energyPolicyPublisher: AnyPublisher<EnergyPolicy, Never>? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.currentMouseLocation = currentMouseLocation
        self.monitorFactory = monitorFactory

        observeLifecycle()
        observeEnergyPolicy(energyPolicyPublisher)
        restartMonitoring()
    }

    private func observeLifecycle() {
        notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.restartMonitoring()
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.restartMonitoring()
            }
            .store(in: &cancellables)

        workspaceNotificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.restartMonitoring()
            }
            .store(in: &cancellables)

        workspaceNotificationCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.restartMonitoring()
            }
            .store(in: &cancellables)
    }

    private func observeEnergyPolicy(_ publisher: AnyPublisher<EnergyPolicy, Never>?) {
        publisher?
            .map(\.eventMonitoringLevel)
            .removeDuplicates()
            .sink { [weak self] level in
                guard let self, self.monitoringLevel != level else { return }
                self.monitoringLevel = level
                self.restartMonitoring()
            }
            .store(in: &cancellables)
    }

    func restartMonitoring() {
        stopMonitoring()
        setupMonitors(level: monitoringLevel)
        mouseLocation.send(currentMouseLocation())
    }

    private func setupMonitors(level: EnergyEventMonitoringLevel) {
        guard level != .disabled else { return }

        // Hover-based Flow Island expansion relies on global mouse-move events. Keep
        // the listener active in both .full and .interactionOnly modes so the
        // "open on hover" / "auto-collapse on leave" settings work by default.
        if level == .full || level == .interactionOnly {
            mouseMoveMonitor = monitorFactory(.mouseMoved) { [weak self] _ in
                guard let self else { return }
                self.mouseLocation.send(self.currentMouseLocation())
            }
            mouseMoveMonitor?.start()
        }

        mouseDownMonitor = monitorFactory(.leftMouseDown) { [weak self] event in
            self?.mouseDown.send(event)
        }
        mouseDownMonitor?.start()

        mouseDraggedMonitor = monitorFactory(.leftMouseDragged) { [weak self] event in
            guard let self else { return }
            self.mouseLocation.send(self.currentMouseLocation())
            self.mouseDragged.send(event)
        }
        mouseDraggedMonitor?.start()

        mouseUpMonitor = monitorFactory(.leftMouseUp) { [weak self] event in
            self?.mouseUp.send(event)
        }
        mouseUpMonitor?.start()

        // A global key monitor is required for hover-opened panels because the
        // non-activating Flow Island does not own keyboard focus in that state.
        keyDownMonitor = monitorFactory(.keyDown) { [weak self] event in
            self?.keyDown.send(event)
        }
        keyDownMonitor?.start()
    }

    private func stopMonitoring() {
        mouseMoveMonitor?.stop()
        mouseMoveMonitor = nil
        mouseDownMonitor?.stop()
        mouseDownMonitor = nil
        mouseDraggedMonitor?.stop()
        mouseDraggedMonitor = nil
        mouseUpMonitor?.stop()
        mouseUpMonitor = nil
        keyDownMonitor?.stop()
        keyDownMonitor = nil
    }
}
