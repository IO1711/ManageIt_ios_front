import Foundation
import Observation

@MainActor
@Observable
final class ExhibitionsFeatureModel {
    var exhibitions: [ExhibitionSummaryResponse] = []
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
    private var authenticated: AuthenticatedAPI

    init(
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void,
        onReminderSourcesChanged: @escaping () -> Void
    ) {
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.onReminderSourcesChanged = onReminderSourcesChanged
        self.authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: storedContext,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    func updateStoredContext(_ context: StoredDeviceContext) {
        storedContext = context
        authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: context,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await authenticated.perform { url, token in
                try await self.apiClient.fetchExhibitions(serverURL: url, accessToken: token)
            }
            exhibitions = result.sorted { self.exhibitionSort(lhs: $0, rhs: $1) }
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func exhibitions(for phase: ExhibitionPhase) -> [ExhibitionSummaryResponse] {
        exhibitions.filter { $0.phase == phase }
    }

    func upsertSummary(from detail: ExhibitionDetailResponse) {
        let summary = ExhibitionSummaryResponse(
            id: detail.id,
            name: detail.name,
            locationId: detail.location.id,
            locationPath: detail.location.displayName,
            startDate: detail.startDate,
            endDate: detail.endDate,
            phase: detail.phase,
            itemCount: detail.items.count
        )

        if let index = exhibitions.firstIndex(where: { $0.id == summary.id }) {
            exhibitions[index] = summary
        } else {
            exhibitions.append(summary)
        }

        exhibitions.sort { self.exhibitionSort(lhs: $0, rhs: $1) }
    }

    func makeDetailModel(for exhibitionID: Int64) -> ExhibitionDetailFeatureModel {
        ExhibitionDetailFeatureModel(
            exhibitionID: exhibitionID,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated,
            onReminderSourcesChanged: onReminderSourcesChanged,
            onExhibitionUpdated: { [weak self] detail in
                self?.upsertSummary(from: detail)
            }
        )
    }

    func makeCreateModel() -> ExhibitionEditorFeatureModel {
        ExhibitionEditorFeatureModel(
            mode: .create,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated,
            onReminderSourcesChanged: onReminderSourcesChanged
        )
    }

    private func exhibitionSort(
        lhs: ExhibitionSummaryResponse,
        rhs: ExhibitionSummaryResponse
    ) -> Bool {
        if lhs.phase != rhs.phase {
            return phaseOrder(lhs.phase) < phaseOrder(rhs.phase)
        }
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func phaseOrder(_ phase: ExhibitionPhase) -> Int {
        switch phase {
        case .active:
            return 0
        case .planned:
            return 1
        case .ended:
            return 2
        }
    }
}
