import SwiftUI

struct ItemHistoryView: View {
    let store: ItemHistoryFeatureModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.isLoading && store.entries.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let message = store.errorMessage {
                    inlineMessage(text: message)
                } else if store.entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 30))
                            .foregroundStyle(AppTheme.mutedInk)
                        Text("No movement history yet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Once this item is moved or rented, the history will appear here.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.mutedInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 50)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(store.entries) { entry in
                        HistoryRow(entry: entry)
                    }
                }
            }
            .padding(20)
        }
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.entries.isEmpty {
                await store.load()
            }
        }
        .refreshable {
            await store.load()
        }
    }

    private func inlineMessage(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text).font(.system(size: 13))
            Spacer()
        }
        .foregroundStyle(AppTheme.rejectedText)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(AppTheme.rejectedBg)
        )
    }
}
