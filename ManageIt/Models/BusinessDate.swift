import Foundation

/// Day-precision backend `DATE` value. The architecture stores movement/planning dates
/// as `DATE` (no time, no time zone), so the iPhone app must never round-trip them through
/// timestamp-based `Date` codecs.
struct BusinessDate: Hashable, Comparable, Codable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) throws {
        try BusinessDate.validate(year: year, month: month, day: day)
        self.year = year
        self.month = month
        self.day = day
    }

    init(encodedString: String) throws {
        let trimmed = encodedString.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-")
        guard
            parts.count == 3,
            let y = Int(parts[0]), parts[0].count == 4,
            let m = Int(parts[1]), parts[1].count == 2,
            let d = Int(parts[2]), parts[2].count == 2
        else {
            throw BusinessDateError.invalidFormat(trimmed)
        }
        try self.init(year: y, month: m, day: d)
    }

    init(dateComponents: DateComponents) throws {
        guard
            let y = dateComponents.year,
            let m = dateComponents.month,
            let d = dateComponents.day
        else {
            throw BusinessDateError.invalidComponents
        }
        try self.init(year: y, month: m, day: d)
    }

    var encodedString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    func dateComponents(calendar: Calendar = .current) -> DateComponents {
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        return components
    }

    func date(calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal.date(from: dateComponents(calendar: cal))
    }

    func formattedForDisplay(locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if let resolved = date() {
            return formatter.string(from: resolved)
        }
        return encodedString
    }

    static let today: BusinessDate = {
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let comps = cal.dateComponents([.year, .month, .day], from: now)
        return (try? BusinessDate(dateComponents: comps)) ?? (try! BusinessDate(year: 2026, month: 1, day: 1))
    }()

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        try self.init(encodedString: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedString)
    }

    // MARK: Comparable

    static func < (lhs: BusinessDate, rhs: BusinessDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    // MARK: Validation

    private static func validate(year: Int, month: Int, day: Int) throws {
        guard year >= 1 && year <= 9999 else {
            throw BusinessDateError.invalidComponents
        }
        guard (1...12).contains(month) else {
            throw BusinessDateError.invalidComponents
        }
        guard day >= 1, day <= daysIn(month: month, year: year) else {
            throw BusinessDateError.invalidComponents
        }
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

enum BusinessDateError: LocalizedError {
    case invalidFormat(String)
    case invalidComponents

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let raw):
            return "Could not parse \"\(raw)\" as a YYYY-MM-DD date."
        case .invalidComponents:
            return "The date components do not describe a real calendar day."
        }
    }
}
