import XCTest
import Combine
@testable import CC_FLOW

final class ProductivityFeatureTests: XCTestCase {
    @MainActor
    func testProactiveEventsPublishImmediatelyAndConsumeOnce() async throws {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })
        center.publish(targetFeatureID: LeftFeature.calendarID, kind: .calendarReminderDue, summary: "A")
        let event = try XCTUnwrap(center.latestEvent)
        XCTAssertEqual(event.targetFeatureID, LeftFeature.calendarID)
        XCTAssertEqual(event.kind, .calendarReminderDue)
        XCTAssertEqual(event.summary, "A")
        XCTAssertEqual(event.count, 1)
        XCTAssertTrue(center.consume(event.sequence))
        XCTAssertFalse(center.consume(event.sequence))
    }

    @MainActor
    func testSameFeatureEventsRemainSeparateAndOrdered() async throws {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })
        center.publish(targetFeatureID: LeftFeature.calendarID, kind: .calendarReminderDue, summary: "A")
        center.publish(targetFeatureID: LeftFeature.calendarID, kind: .calendarReminderDue, summary: "B")

        XCTAssertEqual(center.pendingEvents.map(\.kind), [.calendarReminderDue, .calendarReminderDue])
        XCTAssertEqual(center.pendingEvents.map(\.summary), ["A", "B"])
        XCTAssertEqual(center.pendingEvents.map(\.count), [1, 1])
        XCTAssertLessThan(center.pendingEvents[0].sequence, center.pendingEvents[1].sequence)
        let first = try XCTUnwrap(center.nextEvent)
        XCTAssertTrue(center.consume(first.sequence))
        XCTAssertEqual(center.nextEvent?.kind, .calendarReminderDue)
    }

    @MainActor
    func testProactiveEventsAreRejectedAtPublishTimeWhenPolicyBlocksThem() async {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { $0 != LeftFeature.calendarID })
        center.publish(targetFeatureID: LeftFeature.calendarID, kind: .calendarReminderDue, summary: "muted")
        XCTAssertTrue(center.pendingEvents.isEmpty)
    }

    @MainActor
    func testQueueChangeSignalObservesCommittedEvent() async {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })
        var observedEvent: ProductivityProactiveEvent?
        let cancellable = center.queueDidChange.sink {
            observedEvent = center.nextEvent
        }

        center.publish(
            targetFeatureID: LeftFeature.calendarID,
            kind: .calendarReminderDue,
            summary: "saved"
        )

        XCTAssertEqual(observedEvent?.kind, .calendarReminderDue)
        XCTAssertEqual(observedEvent?.summary, "saved")
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testQueueSubscriptionImmediatelyObservesEventPublishedBeforeSubscription() async {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })
        center.publish(
            targetFeatureID: LeftFeature.calendarID,
            kind: .calendarReminderDue,
            summary: "saved-before-subscription"
        )

        var observedEvent: ProductivityProactiveEvent?
        let cancellable = center.queueDidChange.prepend(()).sink {
            observedEvent = center.nextEvent
        }

        XCTAssertEqual(observedEvent?.summary, "saved-before-subscription")
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testQueueSignalCanDrainConsecutiveReminderEventsWithoutRevival() async {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })
        var deliveredKinds: [ProductivityProactiveEventKind] = []
        let cancellable = center.queueDidChange.sink {
            guard let event = center.nextEvent else { return }
            deliveredKinds.append(event.kind)
            XCTAssertTrue(center.consume(event.sequence))
        }

        center.publish(targetFeatureID: LeftFeature.calendarID, kind: .calendarReminderDue, summary: "start")
        center.publish(targetFeatureID: LeftFeature.calendarID, kind: .calendarReminderDue, summary: "complete")

        XCTAssertEqual(deliveredKinds, [.calendarReminderDue, .calendarReminderDue])
        XCTAssertTrue(center.pendingEvents.isEmpty)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testImmediateQueueRetainsNewestHundredEventsInFIFOOrder() async {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })

        for index in 0..<105 {
            center.publish(
                targetFeatureID: LeftFeature.calendarID,
                kind: .calendarReminderDue,
                summary: "event-\(index)"
            )
        }

        XCTAssertEqual(center.pendingEvents.count, 100)
        XCTAssertEqual(center.pendingEvents.first?.summary, "event-5")
        XCTAssertEqual(center.pendingEvents.last?.summary, "event-104")
        XCTAssertEqual(center.pendingEvents.map(\.sequence), Array(6...105))
    }

    func testCalendarActionableRemindersOnlyIncludesOverdueAndToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_720_008_000)
        let reminders = [
            ReminderAgendaItem(id: "past", title: "past", dueDate: now.addingTimeInterval(-86_400), priority: 0),
            ReminderAgendaItem(id: "today", title: "today", dueDate: now.addingTimeInterval(60), priority: 0),
            ReminderAgendaItem(id: "future", title: "future", dueDate: now.addingTimeInterval(172_800), priority: 0),
            ReminderAgendaItem(id: "none", title: "none", dueDate: nil, priority: 0)
        ]
        XCTAssertEqual(CalendarService.actionableReminders(reminders, now: now, calendar: calendar).map(\.id), ["past", "today"])
    }

    func testLocalLeftFeatureConfigurationCreatesWebFeatureAndOptionShortcut() throws {
        let data = Data(#"{"webFeatures":[{"id":"local-tool","name":"Local Tool","url":"http://127.0.0.1:8080/tool","shortcut":{"key":"p","modifiers":["alt"]}}]}"#.utf8)
        let configuration = try JSONDecoder().decode(LocalLeftFeatureConfiguration.self, from: data)
        let features = configuration.merging(into: [])
        let feature = try XCTUnwrap(features.first)

        XCTAssertEqual(feature.id, "local-tool")
        XCTAssertEqual(feature.displayName, "Local Tool")
        XCTAssertEqual(feature.kind, .webURL(url: "http://127.0.0.1:8080/tool"))
        XCTAssertEqual(feature.globalShortcut?.displayString, "⌥ P")
    }

    func testLocalLeftFeatureConfigurationRejectsUnsafeURLScheme() throws {
        let data = Data(#"{"webFeatures":[{"id":"script","name":"Script","url":"javascript:alert(1)"}]}"#.utf8)
        let configuration = try JSONDecoder().decode(LocalLeftFeatureConfiguration.self, from: data)
        XCTAssertTrue(configuration.merging(into: []).isEmpty)
    }
}
