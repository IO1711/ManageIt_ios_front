import Foundation
import Observation
import UserNotifications

/// Centralizes all UNUserNotificationCenter usage so feature models do not
/// reach into the system framework directly. Implements an idempotent
/// reconciliation pattern: each `sync*` call computes the expected reminder
/// set for its slice of data and adjusts the pending notification list to
/// match — cancelling stale reminders and re-adding new ones.
@MainActor
@Observable
final class ReminderCoordinator {
    var permissionStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored
    private let center = UNUserNotificationCenter.current()

    @ObservationIgnored
    private let exhibitionPrefix = "exhibition-end-"

    @ObservationIgnored
    private let rentalPrefix = "rental-return-item-"

    @ObservationIgnored
    /// Local-only notifications fire by default at 10:00 AM museum time on the
    /// target day. Chosen because museum staff usually start their workflow
    /// in the morning and the architecture only specifies the day, not the time.
    private let fireHour = 10

    // MARK: - Permission

    func refreshPermissionStatus() async {
        let settings = await center.notificationSettings()
        permissionStatus = settings.authorizationStatus
    }

    func requestPermissionIfNeeded() async {
        await refreshPermissionStatus()
        guard permissionStatus == .notDetermined else { return }
        await requestPermission()
    }

    func requestPermission() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            // Silent failure — UI surfaces the resulting status either way.
        }
        await refreshPermissionStatus()
    }

    var isAuthorized: Bool {
        permissionStatus == .authorized || permissionStatus == .provisional || permissionStatus == .ephemeral
    }

    // MARK: - Exhibition end reminders

    func syncExhibitionReminders(_ exhibitions: [ExhibitionResponse]) async {
        await refreshPermissionStatus()

        guard isAuthorized else {
            await cancelAllWithPrefix(exhibitionPrefix)
            return
        }

        let now = Date()
        let expected: [PlannedReminder] = exhibitions.compactMap { exhibition in
            // Past-ended exhibitions don't need a reminder anymore.
            guard exhibition.phase != .ended else { return nil }
            guard let fireDate = fireDateForBusinessDay(exhibition.endDate), fireDate > now else { return nil }
            return PlannedReminder(
                identifier: "\(exhibitionPrefix)\(exhibition.id)",
                fireDate: fireDate,
                title: "Exhibition ending today",
                body: "\(exhibition.name) at \(exhibition.locationPath) ends today."
            )
        }

        await reconcile(prefix: exhibitionPrefix, expected: expected)
    }

    // MARK: - Rental return reminders

    /// Aligns the rental reminder for a single item with the currently open
    /// external history row. Pass `openRental == nil` to cancel any existing
    /// reminder for that item (rental closed or item no longer external).
    func syncRentalReminder(
        itemId: Int64,
        itemTitle: String,
        openRental: ItemHistoryEntry?
    ) async {
        await refreshPermissionStatus()
        let identifier = identifierForRental(itemId: itemId)

        guard isAuthorized else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        guard
            let openRental,
            openRental.presenceType == .external,
            let expectedReturn = openRental.expectedReturnDate,
            let returnFireDate = fireDateForBusinessDay(expectedReturn),
            let reminderDate = Calendar.current.date(byAdding: .day, value: -3, to: returnFireDate),
            reminderDate > Date()
        else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        let orgName = openRental.organization?.name ?? "an external organization"
        let reminder = PlannedReminder(
            identifier: identifier,
            fireDate: reminderDate,
            title: "Rental return due in 3 days",
            body: "\(itemTitle) is at \(orgName) and is expected back on \(expectedReturn.formattedForDisplay())."
        )

        await scheduleOrUpdate(reminder)
    }

    func cancelRentalReminder(for itemId: Int64) {
        center.removePendingNotificationRequests(withIdentifiers: [identifierForRental(itemId: itemId)])
    }

    /// Returns the scheduled fire date for a rental return reminder, if one is
    /// currently in the system queue. Used by the UI to display a "Reminder set
    /// for [date]" chip.
    func scheduledRentalReminderDate(for itemId: Int64) async -> Date? {
        let pending = await center.pendingNotificationRequests()
        let identifier = identifierForRental(itemId: itemId)
        guard let request = pending.first(where: { $0.identifier == identifier }),
              let trigger = request.trigger as? UNCalendarNotificationTrigger else {
            return nil
        }
        return trigger.nextTriggerDate()
    }

    /// Same as above for exhibition reminders.
    func scheduledExhibitionReminderDate(for exhibitionId: Int64) async -> Date? {
        let pending = await center.pendingNotificationRequests()
        let identifier = "\(exhibitionPrefix)\(exhibitionId)"
        guard let request = pending.first(where: { $0.identifier == identifier }),
              let trigger = request.trigger as? UNCalendarNotificationTrigger else {
            return nil
        }
        return trigger.nextTriggerDate()
    }

    // MARK: - Helpers

    private func identifierForRental(itemId: Int64) -> String {
        "\(rentalPrefix)\(itemId)"
    }

    private func fireDateForBusinessDay(_ businessDate: BusinessDate) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = businessDate.year
        components.month = businessDate.month
        components.day = businessDate.day
        components.hour = fireHour
        components.minute = 0
        return calendar.date(from: components)
    }

    private func reconcile(prefix: String, expected: [PlannedReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let existingForPrefix = pending.filter { $0.identifier.hasPrefix(prefix) }

        let expectedIds = Set(expected.map(\.identifier))
        let staleIds = existingForPrefix
            .filter { !expectedIds.contains($0.identifier) }
            .map(\.identifier)
        if !staleIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIds)
        }

        for reminder in expected {
            await scheduleOrUpdate(reminder)
        }
    }

    private func scheduleOrUpdate(_ reminder: PlannedReminder) async {
        let pending = await center.pendingNotificationRequests()
        if let existing = pending.first(where: { $0.identifier == reminder.identifier }),
           let trigger = existing.trigger as? UNCalendarNotificationTrigger,
           let nextDate = trigger.nextTriggerDate(),
           abs(nextDate.timeIntervalSince(reminder.fireDate)) < 60,
           existing.content.body == reminder.body {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [reminder.identifier])

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let dateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: reminder.identifier,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    private func cancelAllWithPrefix(_ prefix: String) async {
        let pending = await center.pendingNotificationRequests()
        let toCancel = pending.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier)
        if !toCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toCancel)
        }
    }
}

extension UNAuthorizationStatus {
    var humanReadable: String {
        switch self {
        case .notDetermined: return "Not requested yet"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
}

private struct PlannedReminder {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
}
