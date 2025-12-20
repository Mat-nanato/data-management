import Foundation
import SwiftUI

// ✅ WorkerのURLだけあればいい
let workerURL = URL(string: "https://my-worker.app-lab-nanato.workers.dev")!

// ✅ Workerのレスポンス型
struct WorkerResponse: Codable {
    let reply: String
}

// ✅ レポートモデル（これは今まで通り使える）
struct Report: Codable {
    let storeName: String
    let date: Date
    let sales: Int
    let customerCount: Int
    let wasteAmount: Int
    let orderAmount: Int
    let notes: String
    let lastUpdated: Date
}

// ✅ UserDefaults 保存
func saveReport(_ report: Report) {
    if let data = try? JSONEncoder().encode(report) {
        UserDefaults.standard.set(data, forKey: "lastReport")
    }
}

func loadLastReport() -> Report? {
    guard let data = UserDefaults.standard.data(forKey: "lastReport") else { return nil }
    return try? JSONDecoder().decode(Report.self, from: data)
}

// ✅ 次の火曜4時
func nextTuesday4AM(from date: Date = Date()) -> Date {
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: date)
    let daysUntilTuesday = (3 - weekday + 7) % 7
    let nextTuesday = calendar.date(byAdding: .day, value: daysUntilTuesday, to: date) ?? date
    return calendar.date(bySettingHour: 4, minute: 0, second: 0, of: nextTuesday) ?? nextTuesday
}

func shouldUpdateReport(lastUpdated: Date?) -> Bool {
    guard let last = lastUpdated else { return true }
    return Date() >= nextTuesday4AM(from: last)
}

// ✅ Workerから情報を取るだけ（APIキー不要）
func fetchFamilyMartInfo() async throws -> String {
    var request = URLRequest(url: workerURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 120 // タイムアウトを120秒に延長


    let body: [String: Any] = [
        "prompt": "ファミリーマートの新商品とキャンペーンを簡潔に箇条書きでまとめて"
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, _) = try await URLSession.shared.data(for: request)
    let decoded = try JSONDecoder().decode(WorkerResponse.self, from: data)
    return decoded.reply
}

// ✅ レポート取得（完全完成形）
@MainActor
func loadReport(
    storeName: String,
    sales: Int,
    customerCount: Int,
    wasteAmount: Int,
    orderAmount: Int
) async -> Report? {

    if let lastReport = loadLastReport(), !shouldUpdateReport(lastUpdated: lastReport.lastUpdated) {
        return lastReport
    }

    do {
        let notes = try await fetchFamilyMartInfo()

        let newReport = Report(
            storeName: storeName,
            date: Date(),
            sales: sales,
            customerCount: customerCount,
            wasteAmount: wasteAmount,
            orderAmount: orderAmount,
            notes: notes,
            lastUpdated: Date()
        )

        saveReport(newReport)
        return newReport
    } catch {
        print("データ取得失敗:", error)
        return loadLastReport()
    }
}
