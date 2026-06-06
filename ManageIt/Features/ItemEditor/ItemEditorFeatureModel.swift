import Foundation
import Observation

@MainActor
@Observable
final class ItemEditorFeatureModel: Identifiable {
    let id: UUID = UUID()

    enum EditorMode: Equatable {
        case create
        case edit(itemID: Int64, original: ItemResponse)

        var title: String {
            switch self {
            case .create: return "New item"
            case .edit: return "Edit item"
            }
        }
    }

    var mode: EditorMode
    var mainInventoryNumber: String
    var title: String
    var secondaryDraft: String = ""
    var secondaryInventoryNumbers: [String]
    var selectedAuthors: [AuthorResponse]
    var authorQuery: String = ""
    var authorSuggestions: [AuthorResponse] = []
    var availableLocations: [LocationResponse] = []
    var selectedInitialLocation: LocationResponse?
    var moveInDate: BusinessDate?
    var isSaving: Bool = false
    var isCheckingConflict: Bool = false
    var mainNumberConflict: ItemMainNumberConflictResponse?
    var errorMessage: String?
    var validationMessage: String?
    var saveSucceeded: Bool = false
    var savedItem: ItemResponse?

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

    @ObservationIgnored
    private var authorSearchTask: Task<Void, Never>?

    init(
        mode: EditorMode,
        storedContext: StoredDeviceContext,
        sessionModel: DeviceSessionModel,
        apiClient: ManageItAPIClient,
        onContextUpdated: @escaping (StoredDeviceContext) -> Void,
        onSessionInvalidated: @escaping () -> Void
    ) {
        self.mode = mode
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

        switch mode {
        case .create:
            self.mainInventoryNumber = ""
            self.title = ""
            self.secondaryInventoryNumbers = []
            self.selectedAuthors = []
            self.moveInDate = .today
        case .edit(_, let original):
            self.mainInventoryNumber = original.mainInventoryNumber
            self.title = original.title
            self.secondaryInventoryNumbers = original.secondaryInventoryNumbers
            self.selectedAuthors = original.authors.map { AuthorResponse(id: $0.id, name: $0.name, archived: false) }
            self.moveInDate = nil
        }
    }

    var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    func loadCreateDependencies() async {
        guard case .create = mode else { return }
        do {
            let locations = try await authenticated.perform { url, token in
                try await self.apiClient.fetchLocations(serverURL: url, accessToken: token, includeArchived: false)
            }
            self.availableLocations = locations
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func selectInitialLocation(_ location: LocationResponse) {
        selectedInitialLocation = location
    }

    func searchAuthors(query: String) {
        authorQuery = query
        authorSearchTask?.cancel()
        authorSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.performAuthorSearch(query: query)
        }
    }

    private func performAuthorSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authorSuggestions = []
            return
        }
        do {
            let results = try await authenticated.perform { url, token in
                try await self.apiClient.fetchAuthors(serverURL: url, accessToken: token, query: query, includeArchived: false)
            }
            self.authorSuggestions = results.filter { suggestion in
                !self.selectedAuthors.contains(where: { $0.id == suggestion.id })
            }
        } catch {
            // swallow — author suggestions are non-critical
        }
    }

    func addAuthor(_ author: AuthorResponse) {
        if !selectedAuthors.contains(where: { $0.id == author.id }) {
            selectedAuthors.append(author)
        }
        authorQuery = ""
        authorSuggestions = []
    }

    func removeAuthor(id: Int64) {
        selectedAuthors.removeAll { $0.id == id }
    }

    func createAuthor(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let response = try await authenticated.perform { url, token in
                try await self.apiClient.createAuthor(serverURL: url, accessToken: token, request: AuthorCreateRequest(name: trimmed))
            }
            addAuthor(response)
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    func addSecondaryNumber() {
        let trimmed = secondaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        secondaryInventoryNumbers.append(trimmed)
        secondaryDraft = ""
    }

    func removeSecondaryNumber(at index: Int) {
        guard secondaryInventoryNumbers.indices.contains(index) else { return }
        secondaryInventoryNumbers.remove(at: index)
    }

    func checkMainNumberConflict() async {
        let trimmed = mainInventoryNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            mainNumberConflict = nil
            return
        }
        isCheckingConflict = true
        defer { isCheckingConflict = false }
        do {
            let result = try await authenticated.perform { url, token in
                try await self.apiClient.checkMainInventoryNumberConflict(
                    serverURL: url,
                    accessToken: token,
                    mainInventoryNumber: trimmed
                )
            }
            // Conflict only matters if a different item owns the number
            if case let .edit(itemID, _) = mode,
               let conflict = result.conflictingItem,
               conflict.id == itemID {
                mainNumberConflict = nil
            } else {
                mainNumberConflict = result
            }
        } catch {
            mainNumberConflict = nil
        }
    }

    func submit() async {
        validationMessage = nil
        errorMessage = nil
        guard let request = try? buildRequestOrThrow() else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let item: ItemResponse
            switch request {
            case .create(let payload):
                item = try await authenticated.perform { url, token in
                    try await self.apiClient.createItem(serverURL: url, accessToken: token, request: payload)
                }
            case .update(let itemID, let payload):
                item = try await authenticated.perform { url, token in
                    try await self.apiClient.updateItem(serverURL: url, accessToken: token, itemID: itemID, request: payload)
                }
            }
            savedItem = item
            saveSucceeded = true
        } catch {
            errorMessage = AuthenticatedAPI.userFacing(error)
        }
    }

    // MARK: -

    private enum BuiltRequest {
        case create(ItemCreateRequest)
        case update(itemID: Int64, ItemUpdateRequest)
    }

    private func buildRequestOrThrow() throws -> BuiltRequest {
        let trimmedNumber = mainInventoryNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedNumber.isEmpty {
            validationMessage = "Main inventory number is required."
            throw ManageItError.validationError(validationMessage!)
        }
        if trimmedTitle.isEmpty {
            validationMessage = "Title is required."
            throw ManageItError.validationError(validationMessage!)
        }
        if selectedAuthors.isEmpty {
            validationMessage = "At least one author is required."
            throw ManageItError.validationError(validationMessage!)
        }
        if let conflict = mainNumberConflict, conflict.available == false {
            validationMessage = "Main inventory number already exists."
            throw ManageItError.validationError(validationMessage!)
        }

        let authors = selectedAuthors.map { ItemAuthorInput(id: $0.id, name: nil) }

        switch mode {
        case .create:
            guard let location = selectedInitialLocation, location.isAssignable, !location.archived else {
                validationMessage = "Choose an initial internal leaf location."
                throw ManageItError.validationError(validationMessage!)
            }
            guard let date = moveInDate else {
                validationMessage = "Move-in date is required."
                throw ManageItError.validationError(validationMessage!)
            }
            let request = ItemCreateRequest(
                mainInventoryNumber: trimmedNumber,
                title: trimmedTitle,
                secondaryInventoryNumbers: secondaryInventoryNumbers,
                authors: authors,
                initialLocationId: location.id,
                moveInDate: date
            )
            return .create(request)
        case .edit(let itemID, _):
            let request = ItemUpdateRequest(
                mainInventoryNumber: trimmedNumber,
                title: trimmedTitle,
                secondaryInventoryNumbers: secondaryInventoryNumbers,
                authors: authors
            )
            return .update(itemID: itemID, request)
        }
    }
}
