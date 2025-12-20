import SwiftUI

@MainActor
class FamilyMartInfoViewModel: ObservableObject {
    @Published var latestInfo: String = "読み込み中..."
    @Published var isLoading: Bool = false

    func loadLatestInfo() {
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let info = try await fetchFamilyMartInfo()
                latestInfo = info
            } catch {
                print("情報取得失敗:", error)
                latestInfo = "取得失敗"
            }
        }
    }
}




