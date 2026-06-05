import Foundation
import UserNotifications

@MainActor
final class ReminderCoordinator {
    private let apiClient: ManageItAPIClient
    private let sessionModel: DeviceSessionModel
    private let center: UNUserNotificationCenter
    private let fireHour = 10
    private let fireMinute = 0

    init(
        apiClient: ManageItAPIClient,
        sessionModel: DeviceSessionModel,
        center: UNUserNotificationCenter = .current()
    ) {
        self.apiClient = apiClient
        self.sessionModel = sessionModel
        self.center = center
    }

    func syncAll(
        storedContext: StoredDeviceContext,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) async {
        let authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: storedContext,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )

        do {
            let exhibitions = try await authenticated.perform { url, token in
                try await self.apiClient.fetchExhibitions(serverURL: url, accessToken: token)
            }
            let items = try await authenticated.perform { url, token in
                try await self.apiClient.fetchAllItems(
                    serverURL: url,
                    accessToken: token,
                    includeArchived: false,
                    pageSize: 100
                )
            }
            let reminders = buildReminders(exhibitions: exhibitions, items: items)
            await syncManagedNotifications(reminders)
        } catch {
            // The app already surfaces auth and transport failures elsewhere.
        }
    }

    private func buildReminders(
        exhibitions: [ExhibitionSummaryResponse],
        items: [ItemResponse]
    ) -> [ManagedReminder] {
        var reminders: [ManagedReminder] = []

        for exhibition in exhibitions where exhibition.phase != .ended {
            guard let fireDate = makeReminderDate(for: exhibition.endDate, daysOffset: 0) else {
                continue
            }
            reminders.append(
                ManagedReminder(
                    identifier: "manageit.exhibition.\(exhibition.id)",
                    title: "Exhibition ends today",
                    body: "\(exhibition.name) closes today at \(exhibition.locationPath).",
                    fireDate: fireDate
                )
            )
        }

        for item in items where item.currentPlacement.presenceType == .external {
            guard
                let expectedReturnDate = item.currentPlacement.expectedReturnDate,
                let organizationName = item.currentPlacement.organization?.name,
                let fireDate = makeReminderDate(for: expectedReturnDate, daysOffset: -3)
            else {
                continue
            }

            reminders.append(
                ManagedReminder(
                    identifier: "manageit.rental.\(item.id)",
                    title: "Rental return due in 3 days",
                    body: "\(item.title) should return from \(organizationName) on \(expectedReturnDate.formattedForDisplay()).",
                    fireDate: fireDate
                )
            )
        }

        return reminders
    }

    private func syncManagedNotifications(_ reminders: [ManagedReminder]) async {
        let desiredIdentifiers = Set(reminders.map(\.identifier))
        let existingIdentifiers = Set(await pendingManagedIdentifiers())
        let identifiersToRemove = Array(existingIdentifiers.subtracting(desiredIdentifiers))

        if !identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        }

        guard !reminders.isEmpty else { return }

        let settings = await notificationSettings()

        switch settings.authorizationStatus {
        case .denied:
            await cancelManagedNotifications()
            return
        case .notDetermined:
            let granted = await requestAuthorization()
            if !granted {
                await cancelManagedNotifications()
                return
            }
        default:
            break
        }

        for reminder in reminders {
            let request = makeRequest(from: reminder)
            try? await addNotificationRequest(request)
        }
    }

    func cancelManagedNotifications() async {
        let identifiers = await pendingManagedIdentifiers()
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func makeRequest(from reminder: ManagedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: reminder.identifier,
            content: content,
            trigger: trigger
        )
    }

    private func makeReminderDate(for businessDate: BusinessDate, daysOffset: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        var dayComponents = DateComponents()
        dayComponents.calendar = calendar
        dayComponents.timeZone = calendar.timeZone
        dayComponents.year = businessDate.year
        dayComponents.month = businessDate.month
        dayComponents.day = businessDate.day

        guard
            let dayDate = calendar.date(from: dayComponents),
            let shiftedDate = calendar.date(byAdding: .day, value: daysOffset, to: dayDate)
        else {
            return nil
        }

        var reminderComponents = calendar.dateComponents([.year, .month, .day], from: shiftedDate)
        reminderComponents.hour = fireHour
        reminderComponents.minute = fireMinute
        reminderComponents.second = 0

        guard let reminderDate = calendar.date(from: reminderComponents) else {
            return nil
        }

        return reminderDate > Date() ? reminderDate : nil
    }

    private func isManagedIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("manageit.exhibition.") || identifier.hasPrefix("manageit.rental.")
    }

    private func pendingManagedIdentifiers() async -> [String] {
        let requests = await pendingRequests()
        return requests.map(\.identifier).filter(isManagedIdentifier)
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private struct ManagedReminder {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
}
