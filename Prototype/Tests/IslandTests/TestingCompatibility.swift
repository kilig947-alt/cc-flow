import Testing

func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "") {
    guard lhs != rhs else { return }
    Issue.record(Comment(rawValue: message.isEmpty ? "Expected values to be equal: \(lhs) != \(rhs)" : message))
}

func XCTAssertTrue(_ value: Bool, _ message: String = "") {
    guard !value else { return }
    Issue.record(Comment(rawValue: message.isEmpty ? "Expected true" : message))
}

func XCTAssertFalse(_ value: Bool, _ message: String = "") {
    guard value else { return }
    Issue.record(Comment(rawValue: message.isEmpty ? "Expected false" : message))
}

func XCTAssertNil<T>(_ value: T?, _ message: String = "") {
    guard value != nil else { return }
    Issue.record(Comment(rawValue: message.isEmpty ? "Expected nil" : message))
}

func XCTFail(_ message: String = "Test failed") {
    Issue.record(Comment(rawValue: message))
}
