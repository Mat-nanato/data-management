import SwiftUI
import Foundation
import Combine
import FirebaseFirestore


enum StoreLocation {
    case higashikatsuyama
    case uesugi
    case kimachi
    case denryoku
    case nakayama
    case anyoji
    case rifu

    var regionColumnPrefix: String {
        switch self {
        case .higashikatsuyama, .uesugi, .kimachi, .denryoku, .nakayama:
            return "仙台市青葉区"
        case .anyoji:
            return "仙台市宮城野区"
        case .rifu:
            return "宮城郡利府町"
        }
    }
}

struct DailyTemperature: Identifiable {
    let id = UUID()
    let date: Date
    let max: Double
    let min: Double
}

struct OpenMeteoResponse: Codable {
    struct Daily: Codable {
        let time: [String]               // yyyy-MM-dd 形式
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }
    let daily: Daily
}

@MainActor
final class AppWeatherVM: ObservableObject {
    static let shared = AppWeatherVM()
    @Published var dailyTemperatures: [DailyTemperature] = []
    
    private init() {}
    
    // Open-Meteo JSON から気温データを取得（タイムアウト対応済み）
    func downloadWeatherFromOpenMeteo(for store: StoreLocation) async {
        guard let url = URL(string: store.openMeteoURLString()) else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30 // 秒、必要に応じて延長可能
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            
            var temps: [DailyTemperature] = []
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
            
            for (i, dateStr) in decoded.daily.time.enumerated() {
                if let date = formatter.date(from: dateStr) {
                    let max = decoded.daily.temperature_2m_max[i]
                    let min = decoded.daily.temperature_2m_min[i]
                    temps.append(DailyTemperature(date: date, max: max, min: min))
                }
            }
            
            self.dailyTemperatures = temps
            print("Open-Meteo temperatures loaded:", temps.count)
        } catch {
            print("Open-Meteo fetch failed:", error)
        }
    }
}



// 店舗ごとの URL を返す
extension StoreLocation {
    var csvURL: String {
        switch self {
        case .higashikatsuyama:
            return "https://example.com/higashikatsuyama.csv"
        case .uesugi:
            return "https://example.com/uesugi.csv"
        case .kimachi:
            return "https://example.com/komachi.csv"
        case .denryoku:
            return "https://example.com/denryoku.csv"
        case .nakayama:
            return "https://example.com/nakayama.csv"
        case .anyoji:
            return "https://example.com/anyoji.csv"
        case .rifu:
            return "https://example.com/rifu.csv"
        }
    }
}



class WeatherCSVParser {
    static func parseCSV(_ data: Data, for store: StoreLocation) -> [DailyTemperature] {
        guard let content = String(data: data, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n")
        guard let header = lines.first?.components(separatedBy: ",") else { return [] }

        // 店舗に対応する列を特定
        let maxColName = "\(store.regionColumnPrefix)_max"
        let minColName = "\(store.regionColumnPrefix)_min"

        guard let maxIndex = header.firstIndex(of: maxColName),
              let minIndex = header.firstIndex(of: minColName) else {
            print("CSVに列が見つかりません: \(maxColName), \(minColName)")
            return []
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"


        var results: [DailyTemperature] = []

        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: ",")
            guard cols.count > max(maxIndex, minIndex),
                  let date = formatter.date(from: cols[0]),
                  let maxTemp = Double(cols[maxIndex]),
                  let minTemp = Double(cols[minIndex])
            else { continue }

            results.append(DailyTemperature(date: date, max: maxTemp, min: minTemp))
        }

        return results
    }
}


@MainActor
final class JapaneseHolidayVM: ObservableObject {

    // yyyy-MM-dd : 祝日名
    private(set) var holidays: [String: String] = [:]

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func isHoliday(_ date: Date) -> Bool {
        holidayName(date) != nil
    }

    /// 指定年の祝日を取得
    func load(year: Int) async {
        let urlString = "https://holidays-jp.github.io/api/v1/\(year)/date.json"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            holidays = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            print("祝日API取得失敗:", error)
            holidays = [:]
        }
    }

    /// 祝日名を返す（なければ nil）
    func holidayName(_ date: Date) -> String? {
        let key = formatter.string(from: date)
        return holidays[key]
    }
}

final class PhotoVM: ObservableObject {
    @Published var photoDates: [Date] = [] {
        didSet {
            save()
        }
    }

    private let key = "photoDates"
    private let calendar = Calendar.current

    init() {
        load()
    }

    // 保存
    private func save() {
        let timestamps = photoDates.map { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timestamps, forKey: key)
    }

    // 復元
    private func load() {
        let timestamps = UserDefaults.standard.array(forKey: key) as? [TimeInterval] ?? []
        photoDates = timestamps.map { Date(timeIntervalSince1970: $0) }
    }

    // 同じ日を重複登録しない
    func add(date: Date) {
        if !photoDates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
            photoDates.append(date)
        }
    }
}

struct CustomCalendarView: View {
    @EnvironmentObject var photoVM: PhotoVM
    @Binding var selectedDate: Date
    @State private var currentMonth: Date = Date()
    @StateObject private var holidayVM = JapaneseHolidayVM()
    
    @ObservedObject var weatherVM: AppWeatherVM
   
    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        VStack(spacing: 0) { // ← VStack の spacing を 0 に
            
            // 月送りヘッダ
            HStack {
                Button(action: { changeMonth(-1) }) {
                    Image(systemName: "chevron.left")
                }
                
                Spacer()
                
                Text(monthTitle)
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Button(action: { changeMonth(1) }) {
                    Image(systemName: "chevron.right")
                }
            }
      
            // 曜日
            HStack(spacing: 0) {
                ForEach(["日","月","火","水","木","金","土"], id: \.self) { d in
                    Text(d)
                        .font(.caption)              // ← 小さくする
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)           // ← これが超重要
                        .padding(.vertical, 0)
                        .foregroundColor(
                            d == "日" ? .red :
                                d == "土" ? .blue : .primary
                        )
                }
            }
        
            // 日付グリッド
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 7),
                spacing: 0   // ← ここが決定打
            ) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let holidayName = holidayVM.holidayName(date)
                        CalendarDayCell(
                            date: date,
                            selectedDate: $selectedDate,
                            holidayName: holidayName,
                            dailyTemperatures: weatherVM.dailyTemperatures
                        )
                        .environmentObject(photoVM)
                    } else {
                        Color.clear.frame(height: 0)
                    }
                    
                }
            }
            
        }
        .onAppear {
            currentMonth = selectedDate
            let year = calendar.component(.year, from: currentMonth)
            
            // 祝日データ取得
            Task {
                await holidayVM.load(year: year)
            }
            
            // Open-Meteo データ取得
            Task {
                await AppWeatherVM.shared.downloadWeatherFromOpenMeteo(for: .higashikatsuyama)
            }
        }
    }

    // MARK: - 月変更
    private func changeMonth(_ value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
            selectedDate = newMonth

            let year = calendar.component(.year, from: newMonth)
            Task {
                await holidayVM.load(year: year)
            }
        }
    }

    // MARK: - 月タイトル
    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: currentMonth)
    }

    // MARK: - 月内日付配列
    private var daysInMonth: [Date?] {
        guard
            let range = calendar.range(of: .day, in: .month, for: currentMonth),
            let firstDay = calendar.date(
                from: calendar.dateComponents([.year, .month], from: currentMonth)
            )
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)

        for day in range {
            days.append(
                calendar.date(byAdding: .day, value: day - 1, to: firstDay)
            )
        }

        return days
    }
}

struct CalendarDayCell: View {
    let date: Date
    @Binding var selectedDate: Date
    let holidayName: String?
    let dailyTemperatures: [DailyTemperature]
    
    @EnvironmentObject var photoVM: PhotoVM
    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        let weekday = calendar.component(.weekday, from: date)
        let isSunday = weekday == 1
        let isSaturday = weekday == 7
        let isHoliday = holidayName != nil

        let hasPhoto = photoVM.photoDates.contains {
            calendar.isDate($0, inSameDayAs: date)
        }

        let tempForDay = dailyTemperatures.first { calendar.isDate($0.date, inSameDayAs: date) }
        let trend = temperatureTrend(for: date, dailyTemps: dailyTemperatures)

        VStack(spacing: 2) { // ← 少し余裕
            // 日付
            Text("\(calendar.component(.day, from: date))")
                .font(.headline)
                .foregroundColor(isHoliday || isSunday ? .red : isSaturday ? .blue : .primary)

            // 以下は日付の下エリア
            Group {
                if let name = holidayName {
                    Text(name)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
                
                if hasPhoto {
                    Text("📷")
                        .font(.caption2)
                }

                if let temp = tempForDay {
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            Text("⬆︎\(Int(temp.max))°")
                                .font(.caption2)
                            Text("⬇︎\(Int(temp.min))°")
                                .font(.caption2)
                        }
                        // 前日との差
                        Text(trend)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                } else {
                    // データがない場合も○を表示
                    Text("○")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 55, maxHeight: 65, alignment: .top) // ← 上寄せ＆やや低め
        .padding(.bottom, 3) // ← 下のみ余白確保
        .background(
            calendar.isDate(date, inSameDayAs: selectedDate)
            ? Color.blue.opacity(0.15)
            : Color.clear
        )
        .cornerRadius(6)
        .onTapGesture {
            selectedDate = date
        }
    }
    
    // MARK: - 前日との最高気温差を判定
    private func temperatureTrend(for date: Date, dailyTemps: [DailyTemperature]) -> String {
        guard let today = dailyTemps.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) else {
            return "○"
        }
        
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date),
              let yesterday = dailyTemps.first(where: { calendar.isDate($0.date, inSameDayAs: previousDay) }) else {
            return "○"
        }
        
        if today.max > yesterday.max {
            return "↑\(Int(today.max - yesterday.max))°"
        } else if today.max < yesterday.max {
            return "↓\(Int(yesterday.max - today.max))°"
        } else {
            return "→0°"
        }
    }
}



// バックグラウンド用の Operation は削除
// CSV 取得・パースは AppWeatherVM.downloadWeatherFromOpenMeteo を使用

// もしローカル保存が必要であれば簡易関数を残す
func saveWeatherCSV(data: Data) {
    let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let fileURL = doc.appendingPathComponent("daily_weather.csv")
    do {
        try data.write(to: fileURL)
        print("CSV saved to:", fileURL)
    } catch {
        print("CSV保存失敗:", error)
    }
}

func parseWeatherCSV(data: Data) {
    guard let content = String(data: data, encoding: .utf8) else { return }
    
    var dailyTemperatures: [Date: (max: Double, min: Double)] = [:]
    
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd"
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")

    let lines = content.components(separatedBy: "\n")
    for line in lines.dropFirst() {
        let cols = line.components(separatedBy: ",")
        if cols.count >= 3,
           let date = formatter.date(from: cols[0].trimmingCharacters(in: .whitespaces)),
           let maxTemp = Double(cols[1]),
           let minTemp = Double(cols[2]) {
            dailyTemperatures[date] = (max: maxTemp, min: minTemp)
        }
    }

    DispatchQueue.main.async {
        AppWeatherVM.shared.dailyTemperatures = dailyTemperatures.map { date, temps in
            DailyTemperature(date: date, max: temps.max, min: temps.min)
        }

        print("Loaded temperatures:", AppWeatherVM.shared.dailyTemperatures.count)
    }
}


func loadPastReportPhotoDates(photoVM: PhotoVM) {
    let db = Firestore.firestore()
    
    db.collection("dailyReports")
        .whereField("imageURLs", arrayContainsAny: ["dummy"]) // imageURLsが存在する日報を取得
        .getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            
            let pastDates: [Date] = documents.compactMap { doc in
                guard let dateStr = doc.data()["date"] as? String else { return nil }
                return DateFormatter.yyyyMMdd.date(from: dateStr)
            }
            
            // PhotoVM に登録
            for date in pastDates {
                photoVM.add(date: date)
            }
        }
}

extension StoreLocation {
    func openMeteoURLString() -> String {
        let base = "https://api.open-meteo.com/v1/forecast?daily=temperature_2m_max,temperature_2m_min&timezone=Asia/Tokyo"
        switch self {
        case .higashikatsuyama:
            return base + "&latitude=38.2682&longitude=140.8694"
        case .uesugi:
            return base + "&latitude=38.2695&longitude=140.8690"
        case .kimachi:
            return base + "&latitude=38.2688&longitude=140.8720"
        case .denryoku:
            return base + "&latitude=38.2675&longitude=140.8705"
        case .nakayama:
            return base + "&latitude=38.2810&longitude=140.8760"
        case .anyoji:
            return base + "&latitude=38.2850&longitude=140.8870"
        case .rifu:
            return base + "&latitude=38.3280&longitude=140.9100"
        }
    }
}

func temperatureTrend(for date: Date, dailyTemps: [DailyTemperature], calendar: Calendar = .current) -> String {
    guard let today = dailyTemps.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) else {
        return "○"
    }
    
    // 前日を探す
    guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date),
          let yesterday = dailyTemps.first(where: { calendar.isDate($0.date, inSameDayAs: previousDay) }) else {
        return "○"
    }
    
    if today.max > yesterday.max {
        return "↑\(Int(today.max - yesterday.max))°"
    } else if today.max < yesterday.max {
        return "↓\(Int(yesterday.max - today.max))°"
    } else {
        return "→0°"
    }
}
