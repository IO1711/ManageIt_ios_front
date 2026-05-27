import SwiftUI

struct ContentView: View {
    let appModel: AppModel

    var body: some View {
        Group {
            switch appModel.appPhase {
            case .bootstrapping, .restoring:
                BootstrapView()
            case .pairing:
                PairingFeatureView(
                    store: appModel.pairingModel,
                    onActivateDemoMode: {
                        #if DEBUG
                        appModel.activateDemoMode()
                        #endif
                    }
                )
            case .sessionRecovery:
                SessionRecoveryView(
                    reason: appModel.sessionModel.recoveryReason,
                    pairedDevice: appModel.pairedDevice,
                    onRetry: { appModel.retryRestore() },
                    onLogout: {
                        Task { await appModel.logoutCurrentDevice() }
                    },
                    onClearLocal: { appModel.clearAllLocalPairing() }
                )
            case .active:
                if let inventoryModel = appModel.inventoryModel,
                   let context = appModel.pairedDevice {
                    AuthenticatedRootView(
                        appModel: appModel,
                        inventoryModel: inventoryModel,
                        context: context
                    )
                } else {
                    BootstrapView()
                }
            }
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .task {
            appModel.bootIfNeeded()
        }
    }
}

// MARK: - Bootstrap

struct BootstrapView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(AppTheme.primary)
            Text("ManageIt")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("Restoring your session…")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.canvas.ignoresSafeArea())
    }
}

// MARK: - Session recovery

struct SessionRecoveryView: View {
    let reason: SessionRecoveryReason?
    let pairedDevice: StoredDeviceContext?
    let onRetry: () -> Void
    let onLogout: () -> Void
    let onClearLocal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.rejectedText)
                Text(reason?.headline ?? "Could not restore session")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(reason?.detail ?? "Try restoring again or re-pair this device.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.mutedInk)
            }
            .museumPanel()

            if let device = pairedDevice {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last paired device")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    detailRow("Friendly name", device.friendlyName)
                    detailRow("Role", device.role.displayName)
                    detailRow("Server", device.serverAddress)
                }
                .museumPanel()
            }

            recoveryActionButtons
            Spacer()
        }
        .padding(20)
        .background(AppTheme.canvas.ignoresSafeArea())
    }

    private var recoveryActionButtons: some View {
        VStack(spacing: 10) {
            Button(action: onRetry) {
                Label("Try restoring again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryButtonStyle(fillWidth: true))

            Button(action: onLogout) {
                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(SoftButtonStyle())

            Button(action: onClearLocal) {
                Label("Clear local pairing", systemImage: "trash")
            }
            .buttonStyle(DestructiveButtonStyle())
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.subtleInk)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.ink)
        }
    }
}

// MARK: - Authenticated tab-bar root

struct AuthenticatedRootView: View {
    let appModel: AppModel
    let inventoryModel: InventoryFeatureModel
    let context: StoredDeviceContext

    @State private var selectedTab: Tab = .inventory

    enum Tab: Hashable {
        case inventory
        case locations
        case account
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            InventoryStackView(
                inventoryModel: inventoryModel,
                context: context
            )
            .tabItem {
                Label("Inventory", systemImage: "tray.full.fill")
            }
            .tag(Tab.inventory)

            if context.role.isAdmin {
                NavigationStack {
                    LocationManagementView(store: inventoryModel.makeLocationManagementModel())
                }
                .tabItem {
                    Label("Locations", systemImage: "mappin.and.ellipse")
                }
                .tag(Tab.locations)
            }

            NavigationStack {
                AccountView(appModel: appModel, context: context)
            }
            .tabItem {
                Label("Account", systemImage: "person.crop.circle")
            }
            .tag(Tab.account)
        }
        .tint(AppTheme.primary)
    }
}

// MARK: - Inventory stack with navigation between detail/editor/planning/movement/history

struct InventoryStackView: View {
    @Bindable var inventoryModel: InventoryFeatureModel
    let context: StoredDeviceContext

    @State private var path: [InventoryRoute] = []
    @State private var createModel: ItemEditorFeatureModel?

    enum InventoryRoute: Hashable {
        case detail(Int64)
        case edit(Int64)
        case planning(Int64)
        case movement(Int64)
        case history(Int64)
    }

    var body: some View {
        NavigationStack(path: $path) {
            InventoryFeatureView(
                store: inventoryModel,
                onSelectItem: { id in path.append(.detail(id)) },
                onCreateItem: {
                    createModel = inventoryModel.makeCreateEditorModel()
                }
            )
            .navigationTitle("ManageIt")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: InventoryRoute.self) { route in
                destinationView(for: route)
            }
        }
        .sheet(item: $createModel) { model in
            NavigationStack {
                ItemEditorView(
                    store: model,
                    onCompleted: { _ in
                        createModel = nil
                        Task { await inventoryModel.reload() }
                    },
                    onCancel: { createModel = nil }
                )
            }
        }
    }

    @ViewBuilder
    private func destinationView(for route: InventoryRoute) -> some View {
        switch route {
        case .detail(let id):
            let detailModel = inventoryModel.makeDetailModel(for: id)
            ItemDetailHost(
                detailModel: detailModel,
                onEdit: { path.append(.edit(id)) },
                onUpdatePlanning: { path.append(.planning(id)) },
                onCreateMovement: { path.append(.movement(id)) },
                onShowFullHistory: { path.append(.history(id)) }
            )
        case .edit(let id):
            EditWrapper(
                inventoryModel: inventoryModel,
                itemID: id,
                onCompleted: { _ in path.removeLast() },
                onCancel: { path.removeLast() }
            )
        case .planning(let id):
            PlanningWrapper(
                inventoryModel: inventoryModel,
                itemID: id,
                onCompleted: { _ in path.removeLast() },
                onCancel: { path.removeLast() }
            )
        case .movement(let id):
            MovementWrapper(
                inventoryModel: inventoryModel,
                itemID: id,
                onCompleted: { _ in path.removeLast() },
                onCancel: { path.removeLast() }
            )
        case .history(let id):
            HistoryWrapper(
                inventoryModel: inventoryModel,
                itemID: id
            )
        }
    }
}

// MARK: - Wrapper views that fetch the detail snapshot first

private struct ItemDetailHost: View {
    @Bindable var detailModel: ItemDetailFeatureModel
    let onEdit: () -> Void
    let onUpdatePlanning: () -> Void
    let onCreateMovement: () -> Void
    let onShowFullHistory: () -> Void

    var body: some View {
        ItemDetailView(
            store: detailModel,
            onEdit: onEdit,
            onUpdatePlanning: onUpdatePlanning,
            onCreateMovement: onCreateMovement,
            onShowFullHistory: onShowFullHistory
        )
    }
}

private struct EditWrapper: View {
    let inventoryModel: InventoryFeatureModel
    let itemID: Int64
    let onCompleted: (ItemResponse) -> Void
    let onCancel: () -> Void

    @State private var editorModel: ItemEditorFeatureModel?
    @State private var loadingError: String?

    var body: some View {
        Group {
            if let editorModel {
                ItemEditorView(
                    store: editorModel,
                    onCompleted: { item in
                        inventoryModel.replaceItem(item)
                        onCompleted(item)
                    },
                    onCancel: onCancel
                )
            } else if let loadingError {
                ContentUnavailable(message: loadingError)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.canvas)
            }
        }
        .task {
            let detail = inventoryModel.makeDetailModel(for: itemID)
            await detail.load()
            if let model = detail.makeEditorModel() {
                self.editorModel = model
            } else {
                self.loadingError = detail.errorMessage ?? "Could not load item."
            }
        }
    }
}

private struct PlanningWrapper: View {
    let inventoryModel: InventoryFeatureModel
    let itemID: Int64
    let onCompleted: (ItemResponse) -> Void
    let onCancel: () -> Void

    @State private var planningModel: PlanningEditorFeatureModel?
    @State private var loadingError: String?

    var body: some View {
        Group {
            if let planningModel {
                PlanningEditorView(
                    store: planningModel,
                    onCompleted: { item in
                        inventoryModel.replaceItem(item)
                        onCompleted(item)
                    },
                    onCancel: onCancel
                )
            } else if let loadingError {
                ContentUnavailable(message: loadingError)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let detail = inventoryModel.makeDetailModel(for: itemID)
            await detail.load()
            if let model = detail.makePlanningEditorModel() {
                self.planningModel = model
            } else {
                self.loadingError = detail.errorMessage ?? "Could not load item."
            }
        }
    }
}

private struct MovementWrapper: View {
    let inventoryModel: InventoryFeatureModel
    let itemID: Int64
    let onCompleted: (ItemResponse) -> Void
    let onCancel: () -> Void

    @State private var movementModel: MovementFeatureModel?
    @State private var loadingError: String?

    var body: some View {
        Group {
            if let movementModel {
                MovementEntryView(
                    store: movementModel,
                    onCompleted: { item in
                        inventoryModel.replaceItem(item)
                        onCompleted(item)
                    },
                    onCancel: onCancel
                )
            } else if let loadingError {
                ContentUnavailable(message: loadingError)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let detail = inventoryModel.makeDetailModel(for: itemID)
            await detail.load()
            if let model = detail.makeMovementModel() {
                self.movementModel = model
            } else {
                self.loadingError = detail.errorMessage ?? "Could not load item."
            }
        }
    }
}

private struct HistoryWrapper: View {
    let inventoryModel: InventoryFeatureModel
    let itemID: Int64

    @State private var historyModel: ItemHistoryFeatureModel?

    var body: some View {
        Group {
            if let historyModel {
                ItemHistoryView(store: historyModel)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let detail = inventoryModel.makeDetailModel(for: itemID)
            self.historyModel = detail.makeHistoryModel()
        }
    }
}

private struct ContentUnavailable: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.rejectedText)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.mutedInk)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.canvas)
    }
}

// MARK: - Account / session tab

struct AccountView: View {
    let appModel: AppModel
    let context: StoredDeviceContext

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 30))
                            .foregroundStyle(AppTheme.primary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.friendlyName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                            StatusTag(
                                text: context.role.displayName,
                                kind: context.role == .admin ? .admin : .editor
                            )
                        }
                        Spacer()
                    }
                }
                .museumPanel()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Device")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    detailRow("Device type", context.deviceType.displayName)
                    detailRow("Server", context.serverAddress)
                    detailRow("Device id", context.deviceId.uuidString)
                    detailRow(
                        "Refresh expires",
                        context.refreshTokenExpiresAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                .museumPanel()

                Button {
                    Task { await appModel.logoutCurrentDevice() }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(DestructiveButtonStyle())
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.subtleInk)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.ink)
        }
    }
}

#Preview {
    ContentView(appModel: AppModel())
}
