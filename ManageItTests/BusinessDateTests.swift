import XCTest
@testable import ManageIt

final class BusinessDateTests: XCTestCase {

    // MARK: - String parsing

    func testDecodesValidYYYYMMDDString() throws {
        let date = try BusinessDate(encodedString: "2026-09-15")
        XCTAssertEqual(date.year, 2026)
        XCTAssertEqual(date.month, 9)
        XCTAssertEqual(date.day, 15)
    }

    func testDecodeRejectsMissingZeroPadding() {
        XCTAssertThrowsError(try BusinessDate(encodedString: "2026-9-15"))
        XCTAssertThrowsError(try BusinessDate(encodedString: "2026-09-5"))
    }

    func testDecodeRejectsWrongSeparator() {
        XCTAssertThrowsError(try BusinessDate(encodedString: "2026/09/15"))
        XCTAssertThrowsError(try BusinessDate(encodedString: "20260915"))
    }

    func testDecodeRejectsNonNumeric() {
        XCTAssertThrowsError(try BusinessDate(encodedString: "abcd-09-15"))
    }

    func testDecodeRejectsExtraWhitespaceInside() {
        XCTAssertThrowsError(try BusinessDate(encodedString: "2026- 09-15"))
    }

    func testDecodeTrimsOuterWhitespace() throws {
        let date = try BusinessDate(encodedString: "  2026-09-15  ")
        XCTAssertEqual(date.encodedString, "2026-09-15")
    }

    // MARK: - Round-trip

    func testEncodeRoundTrip() throws {
        let original = try BusinessDate(year: 2026, month: 1, day: 7)
        let json = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BusinessDate.self, from: json)
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.encodedString, "2026-01-07")
    }

    func testJSONEncodedAsString() throws {
        let date = try BusinessDate(year: 2026, month: 5, day: 27)
        let data = try JSONEncoder().encode(date)
        let asString = String(data: data, encoding: .utf8)
        XCTAssertEqual(asString, "\"2026-05-27\"")
    }

    // MARK: - Bounds

    func testMonthBoundsRejected() {
        XCTAssertThrowsError(try BusinessDate(year: 2026, month: 0, day: 1))
        XCTAssertThrowsError(try BusinessDate(year: 2026, month: 13, day: 1))
    }

    func testDayBoundsRejected() {
        XCTAssertThrowsError(try BusinessDate(year: 2026, month: 1, day: 0))
        XCTAssertThrowsError(try BusinessDate(year: 2026, month: 1, day: 32))
        XCTAssertThrowsError(try BusinessDate(year: 2026, month: 4, day: 31)) // 30 days in April
        XCTAssertThrowsError(try BusinessDate(year: 2026, month: 2, day: 30))
    }

    func testYearBoundsRejected() {
        XCTAssertThrowsError(try BusinessDate(year: 0, month: 1, day: 1))
        XCTAssertThrowsError(try BusinessDate(year: -1, month: 1, day: 1))
        XCTAssertThrowsError(try BusinessDate(year: 10000, month: 1, day: 1))
    }

    // MARK: - Leap years

    func testLeapYearFeb29Accepted() throws {
        let date = try BusinessDate(year: 2024, month: 2, day: 29)
        XCTAssertEqual(date.encodedString, "2024-02-29")
    }

    func testNonLeapYearFeb29Rejected() {
        XCTAssertThrowsError(try BusinessDate(year: 2023, month: 2, day: 29))
    }

    func testCenturyNonLeap() {
        XCTAssertThrowsError(try BusinessDate(year: 1900, month: 2, day: 29))
    }

    func testCenturyDivisibleBy400IsLeap() throws {
        let date = try BusinessDate(year: 2000, month: 2, day: 29)
        XCTAssertEqual(date.day, 29)
    }

    // MARK: - Comparable / Hashable

    func testComparable() throws {
        let a = try BusinessDate(year: 2026, month: 5, day: 27)
        let b = try BusinessDate(year: 2026, month: 5, day: 28)
        let c = try BusinessDate(year: 2026, month: 6, day: 1)
        let d = try BusinessDate(year: 2027, month: 1, day: 1)
        XCTAssertLessThan(a, b)
        XCTAssertLessThan(b, c)
        XCTAssertLessThan(c, d)
        XCTAssertEqual(a, try BusinessDate(year: 2026, month: 5, day: 27))
    }

    func testHashableEquality() throws {
        let a = try BusinessDate(year: 2026, month: 5, day: 27)
        let b = try BusinessDate(year: 2026, month: 5, day: 27)
        var set = Set<BusinessDate>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - DateComponents

    func testFromValidDateComponents() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 27
        let date = try BusinessDate(dateComponents: components)
        XCTAssertEqual(date.encodedString, "2026-05-27")
    }

    func testFromIncompleteDateComponentsThrows() {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        // day is missing
        XCTAssertThrowsError(try BusinessDate(dateComponents: components))
    }

    func testDateComponentsRoundTrip() throws {
        let date = try BusinessDate(year: 2026, month: 5, day: 27)
        let components = date.dateComponents()
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 27)
    }

    // MARK: - Today

    func testTodayIsPresent() {
        let today = BusinessDate.today
        XCTAssertGreaterThan(today.year, 2020)
        XCTAssertTrue((1...12).contains(today.month))
        XCTAssertTrue((1...31).contains(today.day))
    }
}
