import SwiftUI
import Charts
import Firebase
import FirebaseFirestore
import FirebaseStorage

let db = Firestore.firestore()

struct CategoryAmount {
    var ff: Double
    var rice: Double
    var openCase: Double
    var other: Double
    var dessert: Double
}

// 日報データ構造体
struct DailyReport {
    var purchase: CategoryAmount
    var waste: CategoryAmount
}

// グラフデータ用構造体
struct GraphData: Identifiable {
    let id = UUID()
    let category: String
    let type: String
    let value: Double
}

struct GraphView: View {
    let storeNames = ["東勝山", "上杉", "木町", "安養寺", "利府", "電力", "中山"]
    let date: Date
    let wasteBudget: Double

    @State private var ffPurchaseInput = ""
    @State private var ricePurchaseInput = ""
    @State private var openCasePurchaseInput = ""
    @State private var otherPurchaseInput = ""
    @State private var dessertPurchaseInput = ""
    @State private var ffWasteInput = ""
    @State private var riceWasteInput = ""
    @State private var openCaseWasteInput = ""
    @State private var otherWasteInput = ""
    @State private var dessertWasteInput = ""
    
    @State private var ffPurchaseInputs: [String: String] = [:]
    @State private var ricePurchaseInputs: [String: String] = [:]
    @State private var openCasePurchaseInputs: [String: String] = [:]
    @State private var otherPurchaseInputs: [String: String] = [:]
    @State private var dessertPurchaseInputs: [String: String] = [:]

    @State private var ffWasteInputs: [String: String] = [:]
    @State private var riceWasteInputs: [String: String] = [:]
    @State private var openCaseWasteInputs: [String: String] = [:]
    @State private var otherWasteInputs: [String: String] = [:]
    @State private var dessertWasteInputs: [String: String] = [:]
    
    // NumberFormatter（TextField でカンマ付き表示用）
    private var numberFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal      // 3桁ごとにカンマ
        f.maximumFractionDigits = 0   // 小数点なし
        return f
    }

    private func calculatedWasteBudget(for date: Date) -> (ff: Int, rice: Int, openCase: Int, other: Int) {
        let waste = wasteBudget
        let weekday = Calendar.current.component(.weekday, from: date)

        var r1 = 0.4, r2 = 0.2, r3 = 0.3, r4 = 0.1

        if weekday == 7 { r1 *= 1.1; r2 *= 1.1; r3 *= 1.1; r4 *= 1.1 }
        if weekday == 1 { r1 *= 0.9; r2 *= 0.9; r3 *= 0.9; r4 *= 0.9 }

        return (
            ff: Int(waste * r1),
            rice: Int(waste * r2),
            openCase: Int(waste * r3),
            other: Int(waste * r4)
        )
    }

    let currentStoreName: String  // どの店舗ページかを指定

    private var reports: [(storeName: String, report: DailyReport)] {
        storeNames.map { store in
            let purchase: CategoryAmount
            let waste: CategoryAmount

            if store == currentStoreName {
                purchase = CategoryAmount(
                    ff: Double(ffPurchaseInput.replacingOccurrences(of: ",", with: "")) ?? 0,
                    rice: Double(ricePurchaseInput.replacingOccurrences(of: ",", with: "")) ?? 0,
                    openCase: Double(openCasePurchaseInput.replacingOccurrences(of: ",", with: "")) ?? 0,
                    other: Double(otherPurchaseInput.replacingOccurrences(of: ",", with: "")) ?? 0,
                    dessert: Double(dessertPurchaseInput.replacingOccurrences(of: ",", with: "")) ?? 0
                )
                waste = CategoryAmount(
                    ff: Double(ffWasteInput.replacingOccurrences(of: ",", with: "")) ?? 0,
                    rice: Double(riceWasteInput.replacingOccurrences(of: ",", with: "")) ?? 0,
                    openCase: Double(openCaseWasteInput.replacingOccurrences(of: ",", with: "")) ?? 0,
                    other: Double(otherWasteInput.replacingOccurrences(of: ",", with: "")) ?? 0,
                    dessert: Double(dessertWasteInput.replacingOccurrences(of: ",", with: "")) ?? 0
                )
            } else {
                purchase = CategoryAmount(
                    ff: Double(ffPurchaseInputs[store]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0,
                    rice: Double(ricePurchaseInputs[store]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0,
                    openCase: Double(openCasePurchaseInputs[store]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0,
                    other: Double(otherPurchaseInputs[store]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0,
                    dessert: Double(dessertPurchaseInputs[store]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
                )
                waste = CategoryAmount(
                    ff: Double(ffWasteInputs[store]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0,
                    rice: Double(riceWasteInputs[store]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0,
                    openCase: Double(openCaseWasteInputs[store]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0,
                    other: Double(otherWasteInputs[store]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0,
                    dessert: Double(dessertWasteInputs[store]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
                )
            }

            return (storeName: store, report: DailyReport(purchase: purchase, waste: waste))
        }
    }

    func saveInputsToFirestore() {
        // 日付文字列でドキュメントID作成
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let docId = dateFormatter.string(from: date)

        let purchase: [String: Any] = [
            "ff": Double(ffPurchaseInput.replacingOccurrences(of: ",", with: "")) ?? 0,
            "rice": Double(ricePurchaseInput.replacingOccurrences(of: ",", with: "")) ?? 0,
            "openCase": Double(openCasePurchaseInput.replacingOccurrences(of: ",", with: "")) ?? 0,
            "other": Double(otherPurchaseInput.replacingOccurrences(of: ",", with: "")) ?? 0,
            "dessert": Double(dessertPurchaseInput.replacingOccurrences(of: ",", with: "")) ?? 0
        ]

        let waste: [String: Any] = [
            "ff": Double(ffWasteInput.replacingOccurrences(of: ",", with: "")) ?? 0,
            "rice": Double(riceWasteInput.replacingOccurrences(of: ",", with: "")) ?? 0,
            "openCase": Double(openCaseWasteInput.replacingOccurrences(of: ",", with: "")) ?? 0,
            "other": Double(otherWasteInput.replacingOccurrences(of: ",", with: "")) ?? 0,
            "dessert": Double(dessertWasteInput.replacingOccurrences(of: ",", with: "")) ?? 0
        ]


        let data: [String: Any] = [
            "purchase": purchase,
            "waste": waste,
            "date": Timestamp(date: date)
        ]

        db.collection("stores")
          .document(currentStoreName)
          .collection("dailyReports")
          .document(docId) // ← ここを timeInterval から docId に変更
          .setData(data) { error in
              if let error = error {
                  print("Firestore 保存エラー: \(error.localizedDescription)")
              } else {
                  print("Firestore 保存成功")
              }
          }
    }

    private func formatNumber(_ value: Double) -> String {
        return numberFormatter.string(from: NSNumber(value: Int(value))) ?? "0"
    }

    func loadAllStoresFromFirestore() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let docId = dateFormatter.string(from: date)
        
        for store in storeNames {
            db.collection("stores")
              .document(store)
              .collection("dailyReports")
              .document(docId)
              .getDocument { snapshot, error in
                  if let data = snapshot?.data() {
                      if let purchase = data["purchase"] as? [String: Any] {
                          // ← ここに書く
                          if store == currentStoreName {
                              ffPurchaseInput = formatNumber(purchase["ff"] as? Double ?? 0)
                              ricePurchaseInput = formatNumber(purchase["rice"] as? Double ?? 0)
                              openCasePurchaseInput = formatNumber(purchase["openCase"] as? Double ?? 0)
                              _ = purchase["other"] as? Double ?? 0
                              otherPurchaseInput = formatNumber(purchase["other"] as? Double ?? 0)
                              dessertPurchaseInput = formatNumber(purchase["dessert"] as? Double ?? 0)

                          } else {
                              ffPurchaseInputs[store] = formatNumber(purchase["ff"] as? Double ?? 0)
                              ricePurchaseInputs[store] = formatNumber(purchase["rice"] as? Double ?? 0)
                              openCasePurchaseInputs[store] = formatNumber(purchase["openCase"] as? Double ?? 0)
                              _ = purchase["other"] as? Double ?? 0
                              otherPurchaseInput = formatNumber(purchase["other"] as? Double ?? 0)
                              dessertPurchaseInput = formatNumber(purchase["dessert"] as? Double ?? 0)

                          }
                      }
                      
                      if let waste = data["waste"] as? [String: Any] {
                          DispatchQueue.main.async {
                              if store == currentStoreName {
                                  ffWasteInput = formatNumber(waste["ff"] as? Double ?? 0)
                                  riceWasteInput = formatNumber(waste["rice"] as? Double ?? 0)
                                  openCaseWasteInput = formatNumber(waste["openCase"] as? Double ?? 0)
                                  let otherVal = waste["other"] as? Double ?? 0
                                  otherWasteInput = formatNumber(otherVal)
                                  dessertWasteInput = formatNumber(waste["dessert"] as? Double ?? 0)
                              } else {
                                  ffWasteInputs[store] = formatNumber(waste["ff"] as? Double ?? 0)
                                  riceWasteInputs[store] = formatNumber(waste["rice"] as? Double ?? 0)
                                  openCaseWasteInputs[store] = formatNumber(waste["openCase"] as? Double ?? 0)
                                  let otherVal = waste["other"] as? Double ?? 0
                                  otherWasteInputs[store] = formatNumber(otherVal)
                                  dessertWasteInputs[store] = formatNumber(waste["dessert"] as? Double ?? 0)
                              }
                          }
                      }

                  }
              }
        }
    }


    func fetchReportsFromFirestore() {
        let db = Firestore.firestore()
        for store in storeNames {
            db.collection("dailyReports").document(store).getDocument { snapshot, error in
                if let data = snapshot?.data() {
                    ffPurchaseInputs[store] = data["ffPurchase"] as? String ?? "0"
                    ricePurchaseInputs[store] = data["ricePurchase"] as? String ?? "0"
                    // 他カテゴリも同様
                }
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // 店舗別実金額合計グラフ
                Text("店舗別実金額合計（FF+米飯+オープンケース）")
                    .font(.title2)
                    .padding(.bottom, 8)

                Chart {
                    ForEach(reports, id: \.storeName) { item in
                        BarMark(
                            x: .value("店舗", item.storeName),
                            y: .value("金額", item.report.purchaseTotalActual)
                        )
                        .foregroundStyle(.blue)
                        .position(by: .value("タイプ", "仕入れ"))

                        BarMark(
                            x: .value("店舗", item.storeName),
                            y: .value("金額", item.report.wasteTotalActual)
                        )
                        .foregroundStyle(.red)
                        .position(by: .value("タイプ", "廃棄"))
                    }
                }
                .frame(height: 280)
                .padding(.bottom, 25)


                VStack(alignment: .leading, spacing: 6) {
                    Text("食品口座発注予定金額・実金額(青)")
                        .font(.headline)

                    // FF
                    HStack {
                        // 予定値
                        let ffPlan = calculatedWasteBudget(for: date).ff
                        Text("『FF』予定: \(numberFormatter.string(from: NSNumber(value: ffPlan)) ?? "0")円")

                        // 実金額入力
                        TextField("実金額", text: $ffPurchaseInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: ffPurchaseInput) { oldValue, newValue in
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let num = Int(digits) {
                                    ffPurchaseInput = numberFormatter.string(from: NSNumber(value: num)) ?? ""
                                } else {
                                    ffPurchaseInput = ""
                                }
                            }

                        // 円
                        Text("円")
                    }

                    // 米飯
                    HStack {
                        // 予定値
                        let ricePlan = calculatedWasteBudget(for: date).rice
                        Text("『米飯(チルド寿司・チルド弁当含)』予定: \(numberFormatter.string(from: NSNumber(value: ricePlan)) ?? "0")円")

                        // 実金額入力
                        TextField("実金額", text: $ricePurchaseInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: ricePurchaseInput) { oldValue, newValue in
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let num = Int(digits) {
                                    ricePurchaseInput = numberFormatter.string(from: NSNumber(value: num)) ?? ""
                                } else {
                                    ricePurchaseInput = ""
                                }
                            }

                        // 円（実金額の単位）
                        Text("円")
                    }

                    // サンドイッチ・サラダ・パスタ
                    HStack {
                        // 予定値
                        let openCasePlan = calculatedWasteBudget(for: date).openCase
                        Text("『サンドイッチ・サラダ・パスタ』予定: \(numberFormatter.string(from: NSNumber(value: openCasePlan)) ?? "0")円")

                        // 実金額入力
                        TextField("実金額", text: $openCasePurchaseInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: openCasePurchaseInput) { oldValue, newValue in
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let num = Int(digits) {
                                    openCasePurchaseInput = numberFormatter.string(from: NSNumber(value: num)) ?? ""
                                } else {
                                    openCasePurchaseInput = ""
                                }
                            }

                        // 円（実金額の単位）
                        Text("円")
                    }
                    
                    // 菓子・惣菜・食パンマルチパン
                    HStack {
                        // 予定値
                        let otherPlan = calculatedWasteBudget(for: date).other
                        Text("『菓子・惣菜・食パンマルチパン』予定: \(numberFormatter.string(from: NSNumber(value: otherPlan)) ?? "0")円")

                        // 実金額入力
                        TextField("実金額", text: $otherPurchaseInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: otherPurchaseInput) { oldValue, newValue in
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let num = Int(digits) {
                                    otherPurchaseInput = numberFormatter.string(from: NSNumber(value: num)) ?? ""
                                } else {
                                    otherPurchaseInput = ""
                                }
                            }

                        // 円（実金額の単位）
                        Text("円")
                    }

                    // 手作りデザート
                    HStack {
                        // 予定値
                        let dessertPlan = calculatedWasteBudget(for: date).other
                        Text("『手作りデザート』予定: \(numberFormatter.string(from: NSNumber(value: dessertPlan)) ?? "0")円")

                        // 実金額入力
                        TextField("実金額", text: $dessertPurchaseInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: dessertPurchaseInput) { oldValue, newValue in
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let num = Int(digits) {
                                    dessertPurchaseInput = numberFormatter.string(from: NSNumber(value: num)) ?? ""
                                } else {
                                    dessertPurchaseInput = ""
                                }
                            }

                        // 円（実金額の単位）
                        Text("円")
                    }

                }
                .padding(.bottom, 25)


                VStack(alignment: .leading, spacing: 6) {
                    Text("食品口座廃棄予定金額・実金額(赤)")
                        .font(.headline)

                    // FF 廃棄
                    HStack {
                        // 予定値
                        let ffWastePlan = calculatedWasteBudget(for: date).ff
                        Text("『FF』予定: \(numberFormatter.string(from: NSNumber(value: ffWastePlan)) ?? "0")円")

                        // 実金額入力
                        TextField("実金額", text: $ffWasteInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: ffWasteInput) { oldValue, newValue in
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let num = Int(digits) {
                                    ffWasteInput = numberFormatter.string(from: NSNumber(value: num)) ?? ""
                                } else {
                                    ffWasteInput = ""
                                }
                            }

                        // 円（実金額の単位）
                        Text("円")
                    }

                    // 米飯 廃棄
                    HStack {
                        // 予定値
                        let riceWastePlan = calculatedWasteBudget(for: date).rice
                        Text("『米飯(チルド寿司・チルド弁当含)』予定: \(numberFormatter.string(from: NSNumber(value: riceWastePlan)) ?? "0")円")

                        // 実金額入力
                        TextField("実金額", text: $riceWasteInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: riceWasteInput) { oldValue, newValue in
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let num = Int(digits) {
                                    riceWasteInput = numberFormatter.string(from: NSNumber(value: num)) ?? ""
                                } else {
                                    riceWasteInput = ""
                                }
                            }

                        // 円（実金額の単位）
                        Text("円")
                    }

                    // サンドイッチ・サラダ・パスタ 廃棄
                    HStack {
                        // 予定値
                        let openCaseWastePlan = calculatedWasteBudget(for: date).openCase
                        Text("『サンドイッチ・サラダ・パスタ』予定: \(numberFormatter.string(from: NSNumber(value: openCaseWastePlan)) ?? "0")円")

                        // 実金額入力
                        TextField("実金額", text: $openCaseWasteInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: openCaseWasteInput) { oldValue, newValue in
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let num = Int(digits) {
                                    openCaseWasteInput = numberFormatter.string(from: NSNumber(value: num)) ?? ""
                                } else {
                                    openCaseWasteInput = ""
                                }
                            }

                        // 円（実金額の単位）
                        Text("円")
                    }

                    // 菓子・惣菜・食パンマルチパン 廃棄
                    HStack {
                        // 予定値
                        let otherWastePlan = calculatedWasteBudget(for: date).other
                        Text("『菓子・惣菜・食パンマルチパン』予定: \(numberFormatter.string(from: NSNumber(value: otherWastePlan)) ?? "0")円")

                        // 実金額入力
                        TextField("実金額", text: $otherWasteInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: otherWasteInput) { oldValue, newValue in
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let num = Int(digits) {
                                    otherWasteInput = numberFormatter.string(from: NSNumber(value: num)) ?? ""
                                } else {
                                    otherWasteInput = ""
                                }
                            }

                        // 円（実金額の単位）
                        Text("円")
                    }

                    // 手作りデザート 廃棄
                    HStack {
                        // 予定値
                        let dessertWastePlan = calculatedWasteBudget(for: date).other
                        Text("『手作りデザート』予定: \(numberFormatter.string(from: NSNumber(value: dessertWastePlan)) ?? "0")円")

                        // 実金額入力
                        TextField("実金額", text: $dessertWasteInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: dessertWasteInput) { oldValue, newValue in
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let num = Int(digits) {
                                    dessertWasteInput = numberFormatter.string(from: NSNumber(value: num)) ?? ""
                                } else {
                                    dessertWasteInput = ""
                                }
                            }

                        // 円（実金額の単位）
                        Text("円")
                    }
                    
                    Button("保存") {
                        saveInputsToFirestore()
                    }
                    .padding()
                    .buttonStyle(.borderedProminent)

                }
            }
            .padding()
            .onAppear {
                fetchReportsFromFirestore()
                loadAllStoresFromFirestore()
            }
        }
    }
}

// DailyReport の計算用 extension
extension DailyReport {
    var purchaseTotalActual: Double {
        purchase.ff + purchase.rice + purchase.openCase + purchase.other
    }
    var wasteTotalActual: Double {
        waste.ff + waste.rice + waste.openCase + waste.other
    }
}

struct DailyReportData {
    var storeName: String
    var date: TimeInterval
    var sales: Double
    var customerCount: Double
    var wasteAmount: Double
    var orderAmount: Double
    var notes: String
    var imageURLs: [String] = []
}

func dailyTarget(_ monthly: String, date: Date) -> Double {
    let monthlyValue = Double(monthly.replacingOccurrences(of: ",", with: "")) ?? 0
    let days = Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    return monthlyValue / Double(days)
}

func dailyTargetValue(monthly: String, for date: Date) -> Double {
    let raw = Double(monthly.replacingOccurrences(of: ",", with: "")) ?? 0
    let days = Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    return raw / Double(days)
}

func dailyWasteValue(monthly: String, for date: Date) -> Double {
    let raw = Double(monthly.replacingOccurrences(of: ",", with: "")) ?? 0
    let days = Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    return raw / Double(days)
}
// MARK: - 日報入力画面（複数写真対応）
struct DailyReportView: View {
    let storeName: String
    @State var date: Date

    @Binding var monthlySalesTarget: String   // 親ビューの月間売上目標を受け取る
    @Binding var wasteBudget: String          // 親ビューの廃棄予算を受け取る
    @Binding var chatMessages: [Message]      // トーク画面と連携
    
    // 入力用ステート
    @State private var sales: String = ""
    @State private var customerCount: String = ""
    @State private var wasteAmount: String = ""
    @State private var orderAmount: String = ""
    @State private var notes: String = ""
    @State private var monthlyProgress: Double = 0
    @State private var wasteProgress: Double = 0.0
    

    // 写真管理
    @State private var showPOPForm: Bool = false
    @State private var images: [UIImage] = []
    @State private var showPicker = false
    
    @State private var selectedImage: UIImage? = nil
    @Environment(\.dismiss) private var dismiss
    
    @EnvironmentObject var appVM: AppFirestoreVM
    @EnvironmentObject var photoVM: PhotoVM
    

    var body: some View {
        // ▼ まず、ここを VStack の外へ（View return の外側）
        let wasteTarget = dailyTargetValue(monthly: wasteBudget, for: date)
        let wasteValue = Double(wasteAmount.replacingOccurrences(of: ",", with: "")) ?? 0

        var wasteText: String
        var wasteColor: Color

        if wasteValue <= wasteTarget {
            let rate = wasteTarget > 0 ? (wasteTarget / max(wasteValue, 1)) * 100 : 0
            wasteText = String(format: "節約 %.1f%%", rate)
            wasteColor = .green
        } else {
            let overRate = wasteTarget > 0 ? ((wasteValue - wasteTarget) / wasteTarget) * 100 : 0
            wasteText = String(format: "超過 -%.1f%%", overRate)
            wasteColor = .red
        }
 
        return ScrollView  {
 
            VStack(alignment: .leading, spacing: 20) {
                Text("\(storeName) 日報")
                    .font(.title2)
                    .bold()
                
                    .gesture(
                        DragGesture().onEnded { value in
                            let horizontalAmount = value.translation.width

                            if horizontalAmount > 50 {
                                // 右スワイプ → 前日
                                date = Calendar.current.date(byAdding: .day, value: -1, to: date)!
                                loadReport()
                            } else if horizontalAmount < -50 {
                                // 左スワイプ → 翌日
                                date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
                                loadReport()
                            }
                        }
                    )

                // ▼▼▼ 日割り指標カード ▼▼▼
                HStack(spacing: 12) {

                    // 日割り売上
                    VStack(alignment: .leading, spacing: 6) {
                        Text("日割り売上")
                            .font(.caption)
                            .foregroundColor(.white)

                        // 日割り金額
                        let target = dailyTargetValue(monthly: monthlySalesTarget, for: date)

                        Text("\(target, specifier: "%.0f") 円")
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        // ▼▼ 達成率追加 ▼▼
                        let salesValue = Double(sales.replacingOccurrences(of: ",", with: "")) ?? 0
                        let rate = target > 0 ? (salesValue / target) : 0

                        Text("達成率 \(rate * 100, specifier: "%.1f")%")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    .padding()
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.85))
                    .cornerRadius(10)

                    // 日割り廃棄予算

                    // ▼▼▼ 廃棄カード（ここから View） ▼▼▼
                    VStack(alignment: .leading, spacing: 6) {
                        Text("日割り廃棄")
                            .font(.caption)
                            .foregroundColor(.white)

                        Text("\(wasteTarget, specifier: "%.0f") 円")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(wasteText)
                            .foregroundColor(wasteColor)
                            .font(.caption2)
                    }
                    .padding()
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.85))
                    .cornerRadius(10)



                }

                .padding(.horizontal, 2)


                HStack {
                    Button(action: {
                        date = Calendar.current.date(byAdding: .day, value: -1, to: date)!
                        loadReport()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                    }

                    Spacer()

                    Text("日付: \(formattedDate(date))")
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
                        loadReport()
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                    }
                }
                .padding(.vertical, 4)

                    .foregroundColor(.gray)
                
                // 売上入力
                HStack {
                    Text("実売上")
                        .frame(width: 80, alignment: .leading)

                    TextField("金額を入力", text: $sales)
                        .keyboardType(.numberPad)
                        .onChange(of: sales) {
                            // 数字以外を除去
                            let digits = sales.filter { "0123456789".contains($0) }

                            // カンマ付き表示
                            if let number = Double(digits) {
                                let formatter = NumberFormatter()
                                formatter.numberStyle = .decimal
                                sales = formatter.string(from: NSNumber(value: number)) ?? ""
                            } else {
                                sales = ""
                            }

                            // ここで即達成度を計算
                            let dailySalesValue = Double(sales.replacingOccurrences(of: ",", with: "")) ?? 0
                            let dailyTargetValue = dailyTarget(for: date)
                            monthlyProgress = min(max(dailySalesValue / dailyTargetValue, 0.0), 1.0)
                        }
                }

                // 客数入力
                HStack {
                    Text("客数")
                        .frame(width: 80, alignment: .leading)
                    TextField("客数を入力", text: $customerCount)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .onChange(of: customerCount) { oldValue, newValue in
                            let digits = newValue.filter { "0123456789".contains($0) }
                            if let number = Int(digits) {
                                let formatter = NumberFormatter()
                                formatter.numberStyle = .decimal
                                customerCount = formatter.string(from: NSNumber(value: number)) ?? ""
                            } else {
                                customerCount = ""
                            }
                        }
                }

                // 廃棄金額入力
                HStack {
                    Text("実廃棄(原価)")
                        .frame(width: 80, alignment: .leading)
                    TextField("廃棄金額を入力", text: $wasteAmount)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .onChange(of: wasteAmount) { oldValue, newValue in
                            let digits = newValue.filter { "0123456789".contains($0) }
                            if let number = Double(digits) {
                                let formatter = NumberFormatter()
                                formatter.numberStyle = .decimal
                                wasteAmount = formatter.string(from: NSNumber(value: number)) ?? ""
                                
                                // 廃棄予算達成度を更新
                                let target = dailyWasteTarget(for: date)
                                wasteProgress = target > 0 ? min(max(1.0 - (number / target), 0.0), 1.0) : 0.0
                            } else {
                                wasteAmount = ""
                                wasteProgress = 0.0
                            }
                        }
                }

                // 「メモ・特記事項」の文字
                Text("メモ・特記事項")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 4)
                
                // メモ入力用の枠
                TextEditor(text: $notes)
                    .frame(height: 100)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                
                // 写真表示
                if !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(images.indices, id: \.self) { index in
                                Image(uiImage: images[index])
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 150, height: 180)
                                    .cornerRadius(10)
                                    .shadow(radius: 3)
                            }
                        }
                    }
                }
                
                // 写真追加ボタン
                Button("写真を追加") {
                    showPicker = true
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .cornerRadius(10)
                
                // 保存ボタン
                Button(action: saveReport) {
                    Text("保存")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding(.top, 10)
            }
            .padding()
        }
        
        .onAppear {
            loadReport()
        }

        .sheet(isPresented: $showPicker) {
            PhotoPicker(image: $selectedImage)
            
                .onChange(of: selectedImage) { _, newValue in
                    guard let img = newValue else { return }

                    images.append(img)
                    StorePhotoView.saveImage(img, storeName: storeName, date: date)

                    photoVM.add(date: date)

                    selectedImage = nil
                }
        }
    }

    
    private func currentDaySales() -> Double {
        let key = "\(storeName)_\(formattedDate(date))"
        guard let data = UserDefaults.standard.dictionary(forKey: key) else { return 0.0 }

        if let salesInt = data["sales"] as? Int {
            return Double(salesInt)
        } else if let salesStr = data["sales"] as? String,
                  let value = Double(salesStr.replacingOccurrences(of: ",", with: "")) {
            return value
        }
        return 0.0
    }


    private func calculateMonthlyProgress() -> Double {
        guard let monthlyTargetValue = Double(monthlySalesTarget.replacingOccurrences(of: ",", with: "")),
              monthlyTargetValue > 0 else { return 0.0 }
        let total = monthlySalesTotal()
        return min(max(total / monthlyTargetValue, 0.0), 1.0)
    }

    // 日付フォーマット yyyy-MM-dd
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    //売上目標達成率
    private func monthlySalesTotal() -> Double {
        let calendar = Calendar.current
        let today = Date()
        var total: Double = 0
        
        for day in 1...calendar.component(.day, from: today) {
            if let date = calendar.date(bySetting: .day, value: day, of: today) {
                let key = "\(storeName)_\(formattedDate(date))"
                if let data = UserDefaults.standard.dictionary(forKey: key),
                   let salesStr = data["sales"] as? String,
                   let value = Double(salesStr.replacingOccurrences(of: ",", with: "")) {
                    total += value
                }
            }
        }
        return total
    }
    
    // 数字文字列を三桁区切りに変換
    private func formatNumber(_ value: String) -> String {
        let digits = value.filter { "0123456789".contains($0) }
        if let number = Int(digits) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: number)) ?? ""
        } else {
            return ""
        }
    }

    private func salesFor(_ date: Date) -> Double {
        let key = "\(storeName)_\(formattedDate(date))"
        if let data = UserDefaults.standard.dictionary(forKey: key),
           let salesStr = data["sales"] as? String,
           let value = Double(salesStr.replacingOccurrences(of: ",", with: "")) {
            return value
        }
        return 0
    }

    private var dailySalesValue: Double {
        salesFor(date)
    }

    private var dailyAchievement: Double {
        let target = dailyTarget(for: date)
        guard target > 0 else { return 0 }
        return min(max(dailySalesValue / target, 0), 1)
    }

    // MARK: - 写真ピッカー
    struct PhotoPicker: UIViewControllerRepresentable {
        @Binding var image: UIImage?
        
        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.allowsEditing = true
            return picker
        }
        
        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
            let parent: PhotoPicker
            init(_ parent: PhotoPicker) {
                self.parent = parent
            }
            
            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
            ) {
                parent.image =
                info[.editedImage] as? UIImage ??
                info[.originalImage] as? UIImage
                picker.dismiss(animated: true)
            }
        }
        
    }
    // MARK: - 日割り売上目標計算（例: 土曜110%, 日祝90%）
    private func dailyTarget(for date: Date) -> Double {
        let monthly = Double(monthlySalesTarget) ?? 0
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: date)!
        let totalDays = range.count
        let weekday = calendar.component(.weekday, from: date)
        var base = monthly / Double(totalDays)
        switch weekday {
        case 7: base *= 1.1
        case 1: base *= 0.9
        default: break
        }
        return base
    }
    
    // MARK: - 日割り廃棄目標（土日調整あり）
    private func dailyWasteTarget(for date: Date) -> Double {
        let monthlyWaste = Double(wasteBudget) ?? 0
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: date)!
        let totalDays = range.count
        let weekday = calendar.component(.weekday, from: date)
        var base = monthlyWaste / Double(totalDays)
        switch weekday {
        case 7: base *= 1.1
        case 1: base *= 0.9
        default: break
        }
        return base
    }



    // MARK: - 日報保存（画面は閉じない）
    private func saveReport() {
        let key = "\(storeName)_\(formattedDate(date))"
        
        let group = DispatchGroup()
        var uploadedURLs: [String] = []
        
        for img in images {
            group.enter()
            appVM.uploadImage(img) { url in
                if let url = url {
                    uploadedURLs.append(url)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Firestore用の日報データ
            let report = DailyReportData(
                storeName: storeName,
                date: date.timeIntervalSince1970,
                sales: Double(sales.replacingOccurrences(of: ",", with: "")) ?? 0,
                customerCount: Double(customerCount.replacingOccurrences(of: ",", with: "")) ?? 0,
                wasteAmount: Double(wasteAmount.replacingOccurrences(of: ",", with: "")) ?? 0,
                orderAmount: Double(orderAmount.replacingOccurrences(of: ",", with: "")) ?? 0,
                notes: notes,
                imageURLs: uploadedURLs
            )
            appVM.sendDailyReport(report: report)
            
            // UserDefaultsに三桁区切りのまま保存
            let localReport: [String: Any] = [
                "sales": sales,
                "customerCount": customerCount,
                "wasteAmount": wasteAmount,
                "orderAmount": orderAmount,
                "notes": notes,
                "date": date.timeIntervalSince1970,
                "imageURLs": uploadedURLs
            ]
            UserDefaults.standard.set(localReport, forKey: key)
            
            // 写真保存
            for image in images {
                let filename = self.savePhotoToStoreFolder(image: image)
                print("保存した写真: \(filename)")
            }
            
            // チャット通知
            let talkMessage = """
            店名: \(storeName)
            日付: \(self.formattedDate(date))
            売上: \(sales)
            客数: \(customerCount)
            廃棄: \(wasteAmount)
            特記事項: \(notes)
            """
            self.sendToTalk(message: talkMessage)
            self.chatMessages.append(
                Message(text: talkMessage, isMyMessage: true, images: images, imageURLs: uploadedURLs)
            )
            // 日報画面を閉じる
            self.dismiss()
        }
    }

    
    
    // MARK: - トーク送信用関数
    private func sendToTalk(message: String) {
        // 実際はトーク画面に送信する処理
        // とりあえずデバッグ用に出力
        print(message)
    }
    
    // MARK: - 写真を店舗フォルダに保存（過去分も一覧で見れるように）
    @discardableResult
    private func savePhotoToStoreFolder(image: UIImage, date: Date = Date()) -> String {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return ""
        }
        
        // 店舗フォルダ
        let storeFolder = documents.appendingPathComponent(storeName)
        try? fileManager.createDirectory(at: storeFolder, withIntermediateDirectories: true)
        
        // ファイル名に日付を含める
        let dateString = formattedDate(date) // "yyyy-MM-dd"形式など
        let filename = "photo_\(dateString)_\(Date().timeIntervalSince1970).jpg"
        let fileURL = storeFolder.appendingPathComponent(filename)
        
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
        
        return filename
    }
    
    
    func fetchAllStorePhotosGroupedByDate(storeName: String) -> [String: [URL]] {
        var photosByDate: [String: [URL]] = [:]
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return photosByDate
        }
        
        let storeFolder = documents.appendingPathComponent(storeName)
        guard let files = try? fileManager.contentsOfDirectory(at: storeFolder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return photosByDate
        }
        
        for file in files {
            let filename = file.lastPathComponent
            // ファイル名から日付を抽出 (photo_yyyy-MM-dd_timestamp.jpg)
            if let datePart = filename.split(separator: "_").dropFirst().first {
                let dateString = String(datePart)
                photosByDate[dateString, default: []].append(file)
            }
        }
        
        return photosByDate
    }
    
    // MARK: - 日報読み込み
    private func loadReport() {
        let key = "\(storeName)_\(formattedDate(date))"
        if let data = UserDefaults.standard.dictionary(forKey: key) {
            sales = data["sales"] as? String ?? ""
            customerCount = data["customerCount"] as? String ?? ""
            wasteAmount = data["wasteAmount"] as? String ?? ""
            notes = data["notes"] as? String ?? ""
        }
        
        images.removeAll()
        let fileManager = FileManager.default
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let folder = documents
                .appendingPathComponent(storeName)
                .appendingPathComponent(formattedDate(date)) // ← 日付フォルダを追加
            
            if let files = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if let data = try? Data(contentsOf: file),
                       let uiImage = UIImage(data: data) {
                        images.append(uiImage)
                    }
                }
            }
        }
    }

    }

// MARK: - 店舗写真履歴（段落分け・逆順版）
struct StorePhotoView: View {
    let storeName: String
    @State private var photosByDate: [(date: String, images: [UIImage])] = []

    var body: some View {
        ScrollView {
            if photosByDate.isEmpty {
                Text("まだ写真はありません")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(photosByDate, id: \.date) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.date)
                                .font(.headline)
                                .padding(.leading, 8)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                                ForEach(entry.images.indices, id: \.self) { index in
                                    Image(uiImage: entry.images[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipped()
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .navigationTitle("\(storeName) の写真履歴")
        .onAppear(perform: loadPhotosByDate)
    }

    private func loadPhotosByDate() {
        photosByDate.removeAll()
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let storeFolder = documents.appendingPathComponent(storeName)
        guard fileManager.fileExists(atPath: storeFolder.path) else { return }

        // storeName フォルダ以下のすべてのサブフォルダ（日付ごとのフォルダ）を走査
        if let subfolders = try? fileManager.contentsOfDirectory(at: storeFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            // 日付逆順（最新日が上）
            for folder in subfolders.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                var images: [UIImage] = []
                if let files = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                    for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                        if let data = try? Data(contentsOf: file),
                           let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                }
                if !images.isEmpty {
                    photosByDate.append((date: folder.lastPathComponent, images: images))
                }
            }
        }
    }

    // 日報画面から呼び出す用: 写真をフォルダに保存
    static func saveImage(_ image: UIImage, storeName: String, date: Date) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let folder = docs
            .appendingPathComponent(storeName)
            .appendingPathComponent(formattedDateStatic(date))

        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let filename = folder.appendingPathComponent("\(UUID().uuidString).jpg")
        try? data.write(to: filename)
    }

    private static func formattedDateStatic(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// コンテンツビュー
struct ContentView: View {
    let storeName: String
    @Binding var chatMessages: [Message]
    
    @State private var manualWasteBudget = false
    @State private var manualMonthlyTarget = false
    @State private var selectedDate = Date()
    @State private var monthlySalesTarget: String = "" // ← 初期値を空に
    @State private var wasteBudget: String = "500,000"
    @State private var dailyTemperatures: [DailyTemperature] = []
    @StateObject private var weatherVM = AppWeatherVM.shared
    @StateObject private var photoVM = PhotoVM()   // ← 追加
    
    @EnvironmentObject var appVM: AppFirestoreVM
    
    
    // 選択日の売上を取得
    private func salesFor(date: Date) -> Double {
        let key = "\(storeName)_\(formattedDate(date))"
        if let data = UserDefaults.standard.dictionary(forKey: key),
           let salesStr = data["sales"] as? String,
           let value = Double(salesStr.replacingOccurrences(of: ",", with: "")) {
            return value
        }
        return 0
    }
    
    // 選択日の月の合計売上
    private var currentMonthSalesTotal: Double {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: selectedDate)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return 0 }
        
        var total: Double = 0
        for day in range {
            if let date = calendar.date(bySetting: .day, value: day, of: firstOfMonth) {
                total += salesFor(date: date)
            }
        }
        return total
    }
    
    // MARK: - 日割り売上目標
    private func dailyTarget(for date: Date) -> Double {
        let monthly = Double(
            monthlySalesTarget.replacingOccurrences(of: ",", with: "")
        ) ?? 1000
        
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: date)!
        let totalDays = range.count
        let weekday = calendar.component(.weekday, from: date)
        var base = monthly / Double(totalDays)
        switch weekday {
        case 7: base *= 1.1
        case 1: base *= 0.9
        default: break
        }
        return base
    }
    
    private func dailyWasteTarget(for date: Date) -> Double {
        let monthlyWaste = Double(
            wasteBudget.replacingOccurrences(of: ",", with: "")
        ) ?? 50
        
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: date)!
        let totalDays = range.count
        let weekday = calendar.component(.weekday, from: date)
        var base = monthlyWaste / Double(totalDays)
        switch weekday {
        case 1: // 日曜
            base *= 0.9
        case 7: // 土曜
            base *= 1.1
        default: break
        }
        return base
    }
    
    private func formatNumber<T: Numeric>(_ value: T) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(for: value) ?? "0"
    }
    
    // 日付を "yyyy-MM-dd" 文字列に変換
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    
    // 先月売上・客数・客単価を計算
    private func lastMonthSalesTotal() -> Double? {
        let calendar = Calendar.current
        guard let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: Date()),
              let start = calendar.date(from: calendar.dateComponents([.year, .month], from: startOfLastMonth)),
              let range = calendar.range(of: .day, in: .month, for: start) else { return nil }
        
        var totalSales: Double = 0
        var totalCustomers: Double = 0
        
        for day in range {
            let date = calendar.date(byAdding: .day, value: day-1, to: start)!
            let key = "\(storeName)_\(formattedDate(date))"
            if let data = UserDefaults.standard.dictionary(forKey: key),
               let salesStr = data["sales"] as? String,
               let customersStr = data["customerCount"] as? String,
               let sales = Double(salesStr.replacingOccurrences(of: ",", with: "")),
               let customers = Double(customersStr.replacingOccurrences(of: ",", with: "")) {
                totalSales += sales
                totalCustomers += customers
            }
        }
        
        return totalSales > 0 ? totalSales : nil
    }
    
    private func lastMonthCustomersTotal() -> Double? {
        let calendar = Calendar.current
        guard let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: Date()),
              let start = calendar.date(from: calendar.dateComponents([.year, .month], from: startOfLastMonth)),
              let range = calendar.range(of: .day, in: .month, for: start) else { return nil }
        
        var totalCustomers: Double = 0
        
        for day in range {
            let date = calendar.date(byAdding: .day, value: day-1, to: start)!
            let key = "\(storeName)_\(formattedDate(date))"
            if let data = UserDefaults.standard.dictionary(forKey: key),
               let customersStr = data["customerCount"] as? String,
               let customers = Double(customersStr.replacingOccurrences(of: ",", with: "")) {
                totalCustomers += customers
            }
        }
        
        return totalCustomers > 0 ? totalCustomers : nil
    }
    
    private func lastMonthAvgUnit() -> Double? {
        if let sales = lastMonthSalesTotal(), let customers = lastMonthCustomersTotal(), customers > 0 {
            return sales / customers
        }
        return nil
    }
    
    private func dailyAchievement(for date: Date) -> Double {
        let sales = salesFor(date: date)
        let target = dailyTarget(for: date)
        
        guard target > 0 else { return 0 }
        return min(max(sales / target, 0), 1) // 0%〜100%以上は丸め
    }
    
    //先月計算表示
    let lastMonthSales = 1234567
    let lastMonthCustomers = 3456
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                
                HStack(spacing: 16) {
                    // 先月売上
                    VStack {
                        Text("先月売上")
                            .font(.caption)
                            .foregroundColor(.gray)
                        if let total = lastMonthSalesTotal() {
                            Text(formatNumber(total))
                                .font(.headline)
                        } else {
                            Text("データなし")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // 先月客数
                    VStack {
                        Text("先月客数計")
                            .font(.caption)
                            .foregroundColor(.gray)
                        if let total = lastMonthCustomersTotal() {
                            Text(formatNumber(total))
                                .font(.headline)
                        } else {
                            Text("データなし")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // 先月客単価
                    VStack {
                        Text("先月客単価平均")
                            .font(.caption)
                            .foregroundColor(.gray)
                        if let avg = lastMonthAvgUnit() {
                            Text(formatNumber(avg))
                                .font(.headline)
                        } else {
                            Text("データなし")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            
            ScrollView {
                VStack(spacing: 20) {
                    // カレンダー
                    CustomCalendarView(
                        selectedDate: $selectedDate,
                        weatherVM: AppWeatherVM.shared
                    )
                    .environmentObject(photoVM)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    .padding(.horizontal)
                    .onChange(of: selectedDate) {
                        // 選択日が変わったら
                        loadMonthlyLatestValues()    // 全日共通の最後の手入力値を反映
                        loadDailyData(for: selectedDate) // 選択日の個別データがあれば上書き
                    }




                    // カレンダー直後に追加
                    HStack(spacing: 20) {
                        Text("↑：最高気温")
                            .font(.caption)
                            .foregroundColor(.red)
                        
                        Text("↓：最低気温")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Text("○：データ無し or 寒暖差")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                    
                    // ▼▼▼ ここから横並び ▼▼▼
                    HStack(spacing: 12) {
                        
                        // 日割り売上目標
                        NavigationLink(
                            destination: DailyReportView(
                                storeName: storeName,
                                date: selectedDate,
                                monthlySalesTarget: $monthlySalesTarget,
                                wasteBudget: $wasteBudget,
                                chatMessages: $chatMessages
                                
                            )
                            
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("日割り売上")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                
                                Text("\(dailyTarget(for: selectedDate), specifier: "%.0f") 円")
                                
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding()
                            .frame(height: 80)
                            
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(10)
                        }
                        
                        // 日割り廃棄目標
                        NavigationLink(
                            destination: DailyReportView(
                                storeName: storeName,
                                date: selectedDate,
                                monthlySalesTarget: $monthlySalesTarget,
                                wasteBudget: $wasteBudget,
                                chatMessages: $chatMessages
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("日割り廃棄")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                
                                Text("\(dailyWasteTarget(for: selectedDate), specifier: "%.0f") 円")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding()
                            .frame(height: 80)
                            
                            .background(Color.orange.opacity(0.8))
                            .cornerRadius(10)
                        }
                        
                        let graphWasteBudget = 10_000.0
                        
                        NavigationLink(
                            destination: GraphView(
                                date: selectedDate,              // 先に date
                                wasteBudget: graphWasteBudget,   // 次に wasteBudget
                                currentStoreName: storeName      // 最後に currentStoreName
                            )
                        ) {
                            VStack(spacing: 6) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                                
                                Text("グラフ")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding()
                            .frame(height: 80)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    // ▲▲▲ ここまで横並び ▲▲▲
                    
                    // 今月売上目標入力
                    VStack(alignment: .leading, spacing: 5) {
                        Text("今月売上目標")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .onAppear {
                                // 最後に手入力した値を固定キーから読み込む
                                let key = "\(storeName)_latestMonthlySalesTarget"
                                if let saved = UserDefaults.standard.dictionary(forKey: key) {
                                    if let sales = saved["monthlySalesTarget"] as? Int {
                                        monthlySalesTarget = NumberFormatter.localizedString(from: NSNumber(value: sales), number: .decimal)
                                    }
                                    if let waste = saved["wasteBudget"] as? Int {
                                        wasteBudget = NumberFormatter.localizedString(from: NSNumber(value: waste), number: .decimal)
                                    }
                                } else {
                                    // 初回のみ規定値
                                    monthlySalesTarget = "10,000,000"
                                    wasteBudget = "500,000"
                                }
                            }

                        TextField("売上目標", text: $monthlySalesTarget)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                            .onChange(of: monthlySalesTarget) {
                                // oldValue/newValue は不要
                                manualMonthlyTarget = true

                                // 数字だけ抽出して3桁区切り
                                let digits = monthlySalesTarget.filter { "0123456789".contains($0) }
                                if let number = Int(digits) {
                                    let formatter = NumberFormatter()
                                    formatter.numberStyle = .decimal
                                    monthlySalesTarget = formatter.string(from: NSNumber(value: number)) ?? ""

                                    // 最終手入力値として保存
                                    let wasteValue = Int(wasteBudget.replacingOccurrences(of: ",", with: "")) ?? 0
                                    let data: [String: Any] = [
                                        "monthlySalesTarget": number,
                                        "wasteBudget": wasteValue,
                                        "timestamp": ISO8601DateFormatter().string(from: Date())
                                    ]
                                    let key = "\(storeName)_monthlyLatest"
                                    UserDefaults.standard.set(data, forKey: key)
                                } else {
                                    monthlySalesTarget = ""
                                }

                                saveDailyData(for: selectedDate)
                            }

                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) { Spacer() }
                            }

                        // 達成度表示
                        if let monthlyTarget = Double(monthlySalesTarget.replacingOccurrences(of: ",", with: "")) {
                            let progress = min(max(currentMonthSalesTotal / monthlyTarget, 0.0), 1.0)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("今月売上目標達成度: \(Int(progress * 100))%")
                                    .font(.subheadline)
                                    .foregroundColor(progress >= 1 ? .green : .orange)
                                
                                ProgressView(value: progress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: progress >= 1 ? .green : .orange))
                            }
                        } else {
                            EmptyView()
                        }
                        
                    }
                    .padding(.horizontal)
                    
                    // 廃棄予算入力
                    VStack(alignment: .leading, spacing: 5) {
                        Text("今月廃棄予算")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        TextField("例: 500,000円", text: $wasteBudget)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                            .onChange(of: wasteBudget) { oldValue, newValue in
                                // 数字だけ抽出
                                let digits = newValue.filter { "0123456789".contains($0) }
                                if let number = Int(digits) {
                                    // 3桁区切りに変換
                                    let formatter = NumberFormatter()
                                    formatter.numberStyle = .decimal
                                    wasteBudget = formatter.string(from: NSNumber(value: number)) ?? ""
                                    
                                    // 手動入力済みフラグ
                                    manualWasteBudget = true
                                    
                                    // 日付ごとに保存
                                    let key = "\(storeName)_wasteBudget_\(formattedDate(selectedDate))"
                                    UserDefaults.standard.set(wasteBudget, forKey: key)
                                    
                                    // Firestore 保存も必要なら日付ごとに変更
                                } else {
                                    wasteBudget = ""
                                }
                            }
                        
                        
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) { Spacer() }
                            }
                    }
                    
                    .padding(.horizontal)
                    
                    HStack(spacing: 12) {
                        // 日報を開くボタン
                        NavigationLink(destination: DailyReportView(
                            storeName: storeName,
                            date: selectedDate,
                            monthlySalesTarget: $monthlySalesTarget,
                            wasteBudget: $wasteBudget,
                            chatMessages: $chatMessages
                        )) {
                            Text("この日の日報を開く")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.blue)
                                .cornerRadius(10)
                                .shadow(radius: 3)
                        }
                        
                        // 保存ボタン
                        Button(action: {
                            saveDailyData(for: selectedDate)
                        }) {
                            Text("保存")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.green)
                                .cornerRadius(10)
                                .shadow(radius: 3)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    
                    // トーク画面を開く
                    NavigationLink(destination: ChatViewWrapper(messages: $chatMessages)) {
                        Text("トーク画面を開く")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                    .padding(.top, 20)
                } // VStack スクロール内部
                .padding(.horizontal)
            } // ScrollView
            
            Spacer()
        } // VStack 全体
        .navigationTitle(storeName)
        .onAppear {
            loadDailyData(for: selectedDate)
        }
    }
        func loadMonthlyData(for date: Date) {
            let docId = formattedDate(date)
            db.collection("stores")
                .document(storeName)
                .collection("monthlyReports")
                .document(docId)
                .getDocument { snapshot, error in
                    if let data = snapshot?.data() {
                        if let salesTarget = data["monthlySalesTarget"] as? Int {
                            let formatter = NumberFormatter()
                            formatter.numberStyle = .decimal
                            monthlySalesTarget = formatter.string(from: NSNumber(value: salesTarget)) ?? ""
                        }
                        if let wasteBudgetValue = data["monthlyWasteBudget"] as? Int {
                            let formatter = NumberFormatter()
                            formatter.numberStyle = .decimal
                            wasteBudget = formatter.string(from: NSNumber(value: wasteBudgetValue)) ?? ""
                        }
                    } else if let error = error {
                        print("Firestore ロードエラー: \(error.localizedDescription)")
                    }
                }
        }
        
    func saveDailyData(for date: Date) {
        let docId = formattedDate(date)
        
        let salesValue = Int(monthlySalesTarget.replacingOccurrences(of: ",", with: "")) ?? 0
        let wasteValue = Int(wasteBudget.replacingOccurrences(of: ",", with: "")) ?? 0
        
        let data: [String: Any] = [
            "monthlySalesTarget": salesValue,
            "wasteBudget": wasteValue,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        // 日単位保存
        UserDefaults.standard.set(data, forKey: "\(storeName)_dailyData_\(docId)")
        
        // 月単位最新値も更新
        let month = Calendar.current.component(.month, from: date)
        UserDefaults.standard.set(data, forKey: "\(storeName)_monthlyLatest_\(month)")
        
        // Firestore保存も同様に日単位と月単位をセット
    }

        
        func loadDailyData(for date: Date) {
            let docId = formattedDate(date)
            let key = "\(storeName)_dailyData_\(docId)" // 同じキーを使う
            
            // まずUserDefaultsからロード
            if let saved = UserDefaults.standard.dictionary(forKey: key) {
                if let sales = saved["monthlySalesTarget"] as? Int {
                    monthlySalesTarget = NumberFormatter.localizedString(from: NSNumber(value: sales), number: .decimal)
                }
                if let waste = saved["wasteBudget"] as? Int {
                    wasteBudget = NumberFormatter.localizedString(from: NSNumber(value: waste), number: .decimal)
                }
            }
            
            // Firestoreからロード（UserDefaultsより新しいデータがあれば上書き）
            db.collection("stores")
                .document(storeName)
                .collection("dailyReports")
                .document(docId)
                .getDocument { snapshot, error in
                    guard let data = snapshot?.data(), error == nil else { return }
                    if let sales = data["monthlySalesTarget"] as? Int {
                        monthlySalesTarget = NumberFormatter.localizedString(from: NSNumber(value: sales), number: .decimal)
                    }
                    if let waste = data["wasteBudget"] as? Int {
                        wasteBudget = NumberFormatter.localizedString(from: NSNumber(value: waste), number: .decimal)
                    }
                }
        }
    
    func saveMonthlyLatestValues() {
        let salesValue = Int(monthlySalesTarget.replacingOccurrences(of: ",", with: "")) ?? 0
        let wasteValue = Int(wasteBudget.replacingOccurrences(of: ",", with: "")) ?? 0

        let data: [String: Any] = [
            "monthlySalesTarget": salesValue,
            "wasteBudget": wasteValue,
            "timestamp": Timestamp(date: Date())  // ← 文字列ではなく Timestamp
        ]

        // UserDefaults に保存（月ごとキー）
        let monthKey = "\(storeName)_monthlyLatest_\(Calendar.current.component(.month, from: Date()))"
        UserDefaults.standard.set(data, forKey: monthKey)

        // Firestore に保存
        db.collection("stores")
            .document(storeName)
            .collection("monthlyReports")
            .document("latest")
            .setData(data) { error in
                if let error = error {
                    print("Firestore 保存エラー:", error)
                } else {
                    print("最新値保存成功")
                }
            }
    }

    func loadMonthlyLatestValues() {
        let key = "\(storeName)_monthlyLatest"
        if let saved = UserDefaults.standard.dictionary(forKey: key) {
            if let sales = saved["monthlySalesTarget"] as? Int {
                monthlySalesTarget = NumberFormatter.localizedString(from: NSNumber(value: sales), number: .decimal)
            }
            if let waste = saved["wasteBudget"] as? Int {
                wasteBudget = NumberFormatter.localizedString(from: NSNumber(value: waste), number: .decimal)
            }
        }
    }


            // MARK: - 日付を "yyyy-MM-dd" 形式に変換
        private func formattedDateString(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
        
        // MARK: - 先月売上合計（Firestore版）
        private func fetchLastMonthSales(storeName: String, completion: @escaping (Int?) -> Void) {
            let db = Firestore.firestore()
            let calendar = Calendar.current
            let now = Date()
            
            // 先月1日と末日
            guard let startOfLastMonth = calendar.date(
                byAdding: .month, value: -1,
                to: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!),
                  let range = calendar.range(of: .day, in: .month, for: startOfLastMonth),
                  let endOfLastMonth = calendar.date(byAdding: .day, value: range.count - 1, to: startOfLastMonth)
            else {
                completion(nil)
                return
            }
            
            var total = 0
            var hasData = false
            
            let collectionRef = db.collection("shifts").document(storeName).collection("dailyReports")
            
            // Firestore は where 範囲クエリで取得
            let startTimestamp = Timestamp(date: startOfLastMonth)
            let endTimestamp = Timestamp(date: endOfLastMonth)
            
            collectionRef
                .whereField("date", isGreaterThanOrEqualTo: startTimestamp)
                .whereField("date", isLessThanOrEqualTo: endTimestamp)
                .getDocuments { snapshot, error in
                    guard error == nil, let docs = snapshot?.documents, !docs.isEmpty else {
                        completion(nil)
                        return
                    }
                    
                    for doc in docs {
                        if let salesString = doc.data()["sales"] as? String,
                           let value = Int(salesString.replacingOccurrences(of: ",", with: "")) {
                            total += value
                            hasData = true
                        }
                    }
                    completion(hasData ? total : nil)
                }
        }
        
        private func loadDailySummary(for date: Date) {
            let salesKey = "\(storeName)_monthlySalesTarget_\(formattedDate(date))"
            let wasteKey = "\(storeName)_wasteBudget_\(formattedDate(date))"
            
            if let savedSales = UserDefaults.standard.string(forKey: salesKey) {
                monthlySalesTarget = savedSales
            } else {
                monthlySalesTarget = "10,000,000" // デフォルト
            }
            
            if let savedWaste = UserDefaults.standard.string(forKey: wasteKey) {
                wasteBudget = savedWaste
            } else {
                wasteBudget = "500,000" // デフォルト
            }
        }
        
        // MARK: - Firestore 保存
        func saveDailyReport(for date: Date) {
            let db = Firestore.firestore()
            let docKey = formattedDate(date)
            
            let data: [String: Any] = [
                "monthlySalesTarget": monthlySalesTarget,
                "wasteBudget": wasteBudget,
                "timestamp": Timestamp(date: Date())
            ]
            
            db.collection("dailyReports")
                .document(storeName)
                .collection("reports")
                .document(docKey)
                .setData(data) { error in
                    if let error = error {
                        print("保存エラー:", error)
                    } else {
                        print("保存成功")
                    }
                }
        }
        
        // 読み込み
        func loadDailyReport(for date: Date) {
            let db = Firestore.firestore()
            let docKey = formattedDate(date)
            
            db.collection("dailyReports")
                .document(storeName)
                .collection("reports")
                .document(docKey)
                .getDocument { snapshot, error in
                    guard let doc = snapshot, doc.exists, let data = doc.data() else { return }
                    
                    if let sales = data["monthlySalesTarget"] as? String {
                        monthlySalesTarget = sales
                    }
                    if let waste = data["wasteBudget"] as? String {
                        wasteBudget = waste
                    }
                }
        }
    }
    

