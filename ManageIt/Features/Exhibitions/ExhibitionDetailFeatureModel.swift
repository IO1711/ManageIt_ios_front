import Foundation
import Observation

@MainActor
@Observable
final class ExhibitionDetailFeatureModel {
    var exhibitionID: Int64
    var exhibition: ExhibitionDetailResponse?
    var isLoading: Bool = false
    var errorMessage: String?

    var storedContext: StoredDeviceContext

    @ObservationIgnored
    private let sessionModel: DeviceSessionModel

    @ObservationIgnored
    private let apiClient: ManageItAPIClient

    @ObservationIgnored
    private let onContextUpdated: (StoredDeviceContext) -> Void

    @ObservationIgnored
    private let onSessionInvalidated: () -> Void

    @ObservationIgnored
    private let onReminderSourcesChanged: () -> Void

    @ObservationIgnored
    private let onExhibitionUpdated: (ExhibitionDetailResponse) -> Void

    @ObservationIgnored
    private var authenticated: AuthenticatedAPI

    init(
        exhibitionID: Int64,
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void,
        onReminderSourcesChanged: @escaping () -> Void,
        onExhibitionUpdated: @escaping (ExhibitionDetailResponse) -> Void
    ) {
        self.exhibitionID = exhibitionID
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.onReminderSourcesChanged = onReminderSourcesChanged
        self.onExhibitionUpdated = onExhibitionUpdated
        self.authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: storedContext,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let detail = try await authenticated.perform { url, token in
                try await self.apiClient.fetchExhibition(
                    serverURL: url,
                    accessToken: token,
                    exhibitionID: self.exhibitionID
                )
            }
            exhibition = detail
            onExhibitionUpdated(detail)
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func applyUpdatedExhibition(_ detail: ExhibitionDetailResponse) {
        exhibition = detail
        onExhibitionUpdated(detail)
        onReminderSourcesChanged()
    }

    func makeEditorModel() -> ExhibitionEditorFeatureModel? {
        guard let exhibition else { return nil }
        return ExhibitionEditorFeatureModel(
            mode: .edit(existing: exhibition),
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated,
            onReminderSourcesChanged: onReminderSourcesChanged
        )
    }
}
