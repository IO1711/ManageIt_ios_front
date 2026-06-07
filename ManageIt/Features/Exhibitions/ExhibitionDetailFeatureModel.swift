import Foundation
import Observation

@MainActor
@Observable
final class ExhibitionDetailFeatureModel {
    let exhibitionID: Int64
    var exhibition: ExhibitionResponse?
    var isLoading: Bool = false
    var errorMessage: String?

    var storedContext: StoredDeviceContext
    var scheduledReminderDate: Date?

    @ObservationIgnored
    private let sessionModel: DeviceSessionModel

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    let reminderCoordinator: ReminderCoordinator

    @ObservationIgnored
    private let onContextUpdated: (StoredDeviceContext) -> Void

    @ObservationIgnored
    private let onSessionInvalidated: () -> Void

    @ObservationIgnored
    private let onExhibitionUpdated: (ExhibitionResponse) -> Void

    @ObservationIgnored
    private var authenticated: AuthenticatedAPI

    init(
        exhibitionID: Int64,
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        reminderCoordinator: ReminderCoordinator,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void,
        onExhibitionUpdated: @escaping (ExhibitionResponse) -> Void
    ) {
        self.exhibitionID = exhibitionID
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.reminderCoordinator = reminderCoordinator
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.onExhibitionUpdated = onExhibitionUpdated
        self.authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: storedContext,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    var role: DeviceRole { storedContext.role }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await authenticated.perform { url, token in
                try await self.apiClient.fetchExhibition(serverURL: url, accessToken: token, id: self.exhibitionID)
            }
            self.exhibition = result
            self.scheduledReminderDate = await reminderCoordinator
                .scheduledExhibitionReminderDate(for: exhibitionID)
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func applyUpdated(_ updated: ExhibitionResponse) {
        exhibition = updated
        onExhibitionUpdated(updated)
    }

    func makeEditorModel() -> ExhibitionEditorFeatureModel? {
        guard let exhibition else { return nil }
        return ExhibitionEditorFeatureModel(
            mode: .edit(original: exhibition),
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }
}
