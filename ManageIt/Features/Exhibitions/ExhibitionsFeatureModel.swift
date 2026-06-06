import Foundation
import Observation

@MainActor
@Observable
final class ExhibitionsFeatureModel {
    var exhibitions: [ExhibitionResponse] = []
    var phaseFilter: ExhibitionPhase?
    var isLoading: Bool = false
    var hasLoadedOnce: Bool = false
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
    private var authenticated: AuthenticatedAPI

    init(
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) {
        self.storedContext = storedContext
        self.sessionModel = sessionModel
        self.apiClient = apiClient
        self.onContextUpdated = onContextUpdated
        self.onSessionInvalidated = onSessionInvalidated
        self.authenticated = AuthenticatedAPI(
            apiClient: apiClient,
            sessionModel: sessionModel,
            storedContext: storedContext,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    var role: DeviceRole { storedContext.role }

    var filteredExhibitions: [ExhibitionResponse] {
        guard let phaseFilter else { return exhibitions }
        return exhibitions.filter { $0.phase == phaseFilter }
    }

    func setPhaseFilter(_ phase: ExhibitionPhase?) {
        phaseFilter = phase
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        do {
            let result = try await authenticated.perform { url, token in
                try await self.apiClient.fetchExhibitions(serverURL: url, accessToken: token, phase: nil)
            }
            // Sort: active first, then planned, then ended; within each by start date.
            self.exhibitions = result.sorted { lhs, rhs in
                if lhs.phase != rhs.phase {
                    return phaseSortRank(lhs.phase) < phaseSortRank(rhs.phase)
                }
                return lhs.startDate < rhs.startDate
            }
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func replaceExhibition(_ updated: ExhibitionResponse) {
        if let idx = exhibitions.firstIndex(where: { $0.id == updated.id }) {
            exhibitions[idx] = updated
        }
    }

    func makeDetailModel(for id: Int64) -> ExhibitionDetailFeatureModel {
        ExhibitionDetailFeatureModel(
            exhibitionID: id,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated,
            onExhibitionUpdated: { [weak self] updated in
                self?.replaceExhibition(updated)
            }
        )
    }

    func makeCreateEditorModel() -> ExhibitionEditorFeatureModel {
        ExhibitionEditorFeatureModel(
            mode: .create,
            storedContext: storedContext,
            sessionModel: sessionModel,
            apiClient: apiClient,
            onContextUpdated: onContextUpdated,
            onSessionInvalidated: onSessionInvalidated
        )
    }

    private func phaseSortRank(_ phase: ExhibitionPhase) -> Int {
        switch phase {
        case .active: return 0
        case .planned: return 1
        case .ended: return 2
        }
    }
}
