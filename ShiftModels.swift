import SwiftUI
import PDFKit
import FirebaseFirestore

final class UserSession: ObservableObject {
    static let shared = UserSession()

    @Published var isAdmin: Bool = false
    @Published var userName: String = ""
}

func login(userName: String, password: String) {
    UserSession.shared.userName = userName

    // ✅ 管理者判定（例：名前 or ID で判定）
    if userName == "admin" || userName == "manager" {
        UserSession.shared.isAdmin = true
    } else {
        UserSession.shared.isAdmin = false
    }
}

// ✅ どのスタッフの青ラインを合わせても「0〜24が埋まっているか」を判定する関数
func isFullDayCovered(_ shift: DailyShift) -> Bool {
    // 0〜23をすべて false で初期化
    var covered = Array(repeating: false, count: 24)

    for staff in shift.staffShifts {
        for range in staff.ranges {
            let start = max(0, min(23, range.start))
            let end   = max(0, min(24, range.end))

            if start < end {
                for h in start..<end {
                    covered[h] = true
                }
            }
        }
    }

    // すべて true ならフルカバー
    return covered.allSatisfy { $0 }
}

func loadShiftFromFile(date: Date) -> DailyShift? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    let fileName = "shift_\(formatter.string(from: date)).json"
    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = folder.appendingPathComponent(fileName)

    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(DailyShift.self, from: data)
}

func getUncoveredDatesNextTwoWeeks(storeName: String) -> [Date] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    var result: [Date] = []

    for i in 0..<14 {
        guard let date = calendar.date(byAdding: .day, value: i, to: today) else { continue }

        if let shift = loadShiftFromFile(date: date),
           shift.storeName == storeName {

            if isFullDayCovered(shift) == false {
                result.append(date)
            }

        } else {
            // ✅ ファイルが無い日も「未カバー」として扱う
            result.append(date)
        }
    }

    return result
}

class LandscapeHostingController<Content: View>: UIHostingController<Content> {
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
}

struct LandscapeView<Content: View>: UIViewControllerRepresentable {
    @EnvironmentObject var appVM: AppFirestoreVM

    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        LandscapeHostingController(rootView: content)
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - データモデル
struct ShiftRange: Codable, Identifiable, Hashable {
    var id = UUID()   // ← var にすることで decode 時に無視されてもOK
    var start: Int
    var end: Int
}

struct StaffShift: Codable, Identifiable {
    var id = UUID()
    var staffName: String
    var ranges: [ShiftRange]
}

struct DailyShift: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var storeName: String
    var staffShifts: [StaffShift]
}


struct Store: Identifiable {
    let id = UUID()
    var name: String
    var baseShifts: [ShiftRange]
}



// MARK: - 店舗一覧（シフト）
struct ShiftDoorView: View {
    @State private var stores: [Store] = [
        Store(name: "東勝山", baseShifts: [ShiftRange(start: 9, end: 18)]),
        Store(name: "上杉",   baseShifts: [ShiftRange(start: 8, end: 17)]),
        Store(name: "木町",   baseShifts: [ShiftRange(start: 10, end: 19)]),
        Store(name: "安養寺", baseShifts: [ShiftRange(start: 9, end: 18)]),
        Store(name: "利府",   baseShifts: [ShiftRange(start: 7, end: 16)]),
        Store(name: "電力",   baseShifts: [ShiftRange(start: 12, end: 21)]),
        Store(name: "中山",   baseShifts: [ShiftRange(start: 9, end: 18)])
    ]

    @StateObject private var appVM = AppFirestoreVM()

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(stores) { store in
                        NavigationLink(destination:
                            ShiftEditorView(store: store)
                                .environmentObject(appVM)
                        ) {
                            Text(store.name)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("店舗一覧")
        }
    }
}

// MARK: - 日付選択 ＋ シフト画面（最上部 overlay 固定 ＋ 下スクロール確定版）
struct ShiftEditorView: View {

    let store: Store
    @StateObject private var session = UserSession.shared   // ✅ 管理者判定

    @State private var selectedDate: Date = Date()
    @State private var dailyShift: DailyShift?
    @State private var showCalendar = false
    @State private var requireAdminAuth = false   // ✅ 管理者確認アラート用
    @State private var tempAdminUnlock = false    // ✅ この画面だけ一時解除
    @State private var enteredPassword: String = ""
    @State private var showPasswordError: Bool = false    // ✅ PDFプレビュー用
    @State private var showPDFPreview = false
    @State private var pdfDocument: PDFDocument?
    @EnvironmentObject var photoVM: PhotoVM
    @State private var dailyTemperatures: [DailyTemperature] = []
    
    @EnvironmentObject var appVM: AppFirestoreVM

    private let nameColumnWidth: CGFloat = 180
    private let topBarHeight: CGFloat = 48


    var body: some View {
        ZStack(alignment: .top) {

            // ✅ メイン表示
            VStack(spacing: 0) {

                Color.clear
                    .frame(height: topBarHeight)

                GeometryReader { geo in
                    let availableWidth = max(geo.size.width - nameColumnWidth, 1)
                    let hourWidth = availableWidth / 24

                    VStack(spacing: 0) {

                        // ✅ 時間ヘッダー
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: nameColumnWidth, height: 20)

                            ForEach(0..<24, id: \.self) { h in
                                Text("\(h)")
                                    .font(.caption2)
                                    .frame(width: hourWidth, height: 20)
                            }
                        }
                        .frame(height: 20)

                        Divider()

                        // ✅ メイン操作エリア（7日以内タップ検知）
                        ScrollView(.vertical) {
                            if dailyShift != nil {
                                ShiftInputGanttView(
                                    dailyShift: $dailyShift,
                                    store: store,
                                    hourWidth: hourWidth
                                )
                            } else {
                                Text("日付を選択してください")
                                    .foregroundColor(.gray)
                                    .padding(.top, 20)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isWithin7Days(selectedDate) && !session.isAdmin && !tempAdminUnlock {
                                requireAdminAuth = true   // ✅ 管理者確認発動
                            }
                        }
                    }
                }
            }

            // ✅ 最上部固定バー
            HStack(spacing: 12) {

                // ✅ 日付タップ → カレンダー表示
                Button {
                    showCalendar = true
                } label: {
                    Text(formattedDate(selectedDate))
                        .font(.headline)
                }
                .buttonStyle(.plain)

                Spacer()

                // ✅ ＜ 前日へ
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    tempAdminUnlock = false
                    dailyShift = loadDailyShift()
                    propagateToFutureSameWeekday()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .padding(.horizontal, 6)
                }

                // ✅ 店舗名（中央）
                Text(store.name)
                    .font(.headline)
                    .lineLimit(1)

                // ✅ ＞ 翌日へ
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    tempAdminUnlock = false
                    dailyShift = loadDailyShift()
                    propagateToFutureSameWeekday()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .padding(.horizontal, 6)
                }

                Spacer()

                Button("印刷") {
                    // dailyShift が nil でなければ PDF を生成してプレビュー表示
                    guard let shift = dailyShift,
                          let pdf = generateWeeklyShiftPDFWithGanttAndTotal(for: shift) else { return }

                    pdfDocument = pdf         // ✅ PDFをStateに保持
                    showPDFPreview = true     // ✅ シート表示用フラグ
                }
                .sheet(isPresented: $showPDFPreview) {
                    // PDFプレビュー画面
                    if let pdfDocument = pdfDocument {
                        PDFPreviewSheet(pdfDocument: pdfDocument)
                    } else {
                        Text("PDF生成に失敗しました")
                            .foregroundColor(.red)
                            .padding()
                    }
                }

            }
            .padding(.horizontal)
            .frame(height: topBarHeight)
            .background(Color(.systemGray6))

        }
        .ignoresSafeArea(edges: .top)

        // ✅ カレンダー
        .sheet(isPresented: $showCalendar) {

            HStack(spacing: 0) {

                // ✅ 左：シフト不足日
                UncoveredDateListView(store: store) { date in
                    selectedDate = date
                    tempAdminUnlock = false
                    dailyShift = loadDailyShift()
                    propagateToFutureSameWeekday()
                    showCalendar = false
                }
                .frame(width: 240)
                .background(Color(.systemGray6))

                // ✅ 区切り線①
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1)

                // ✅ 中：カレンダー専用カラム
                VStack {
                    CustomCalendarView(
                        selectedDate: $selectedDate,
                        weatherVM: AppWeatherVM.shared
                    )
                    .environmentObject(photoVM)

                    .padding(.top, 12)
                    .padding(.horizontal, 4)
                    .onChange(of: selectedDate) {
                        showCalendar = false
                        tempAdminUnlock = false
                        dailyShift = loadDailyShift()
                        propagateToFutureSameWeekday()
                    }


                    Button("閉じる") {
                        showCalendar = false
                    }
                    .padding(.vertical, 8)
                }
                .frame(width: 360)   // ✅ ← カレンダーの“横幅”をここで確定

                // ✅ 区切り線②（今まで存在しなかった）
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1)

                // ✅ 右：週間勤務集計（← ここが“新しく生まれる”）
                WeeklyStaffSummaryView(store: store)
                    .frame(width: 280)
                    .background(Color(.systemGroupedBackground))
            }
            .padding(0)
            .presentationDetents([.large])
        }


        // --- 管理者パスワード入力シート ---
        .sheet(isPresented: $requireAdminAuth) {
            VStack(spacing: 20) {
                Text("この日付は7日以内のため、管理者のみ編集可能です。")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                SecureField("パスワードを入力", text: $enteredPassword)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .padding(.horizontal)

                HStack {
                    Button("キャンセル") {
                        enteredPassword = ""
                        requireAdminAuth = false
                    }
                    .padding()

                    Button("確認") {
                        if enteredPassword == "8831" {
                            session.isAdmin = true
                            tempAdminUnlock = true
                            enteredPassword = ""
                            requireAdminAuth = false
                        } else {
                            enteredPassword = ""
                            showPasswordError = true
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }

        // パスワード間違い時
        .alert("パスワードエラー", isPresented: $showPasswordError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("パスワードが違います。")
        }


        // --- パスワード間違い時アラート ---
        .alert("パスワードエラー", isPresented: $showPasswordError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("パスワードが違います。")
        }

        .onAppear {
            dailyShift = loadDailyShift()
            propagateToFutureSameWeekday()
        }
    }

    // ✅ 今日から7日以内判定
    private func isWithin7Days(_ date: Date) -> Bool {
        let start = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        let diff = Calendar.current.dateComponents([.day], from: start, to: target).day ?? 0
        return diff >= 0 && diff < 7
    }

    func loadDailyShift() -> DailyShift {
        DailyShift(
            date: selectedDate,
            storeName: store.name,
            staffShifts: (0..<12).map { _ in
                StaffShift(staffName: "", ranges: [])
            }
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日（EEE）"
        return f.string(from: date)
    }

    private func propagateToFutureSameWeekday() {
        guard let shift = dailyShift else { return }

        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: shift.date)
        let futureDates = getFutureDates(days: 30)

        for staff in shift.staffShifts {
            guard let staffIndex = shift.staffShifts.firstIndex(where: { $0.id == staff.id }) else { continue }

            for date in futureDates where calendar.component(.weekday, from: date) == currentWeekday {
                var newShift = shift
                newShift.date = date
                newShift.staffShifts[staffIndex] = staff
                saveShiftToFile(newShift)
            }
        }
    }

    private func getFutureDates(days: Int = 30) -> [Date] {
        (0..<days).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Date())
        }
    }

    private func saveShiftToFile(_ shift: DailyShift) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let fileName = "shift_\(f.string(from: shift.date)).json"
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = folder.appendingPathComponent(fileName)

        if let data = try? JSONEncoder().encode(shift) {
            try? data.write(to: url)
        }
    }
}

// MARK: - スタッフ名入力 ＋ ガントチャート（スクロール安定版 + 保存対応）
struct ShiftInputGanttView: View {
    @StateObject private var session = UserSession.shared
    @Binding var dailyShift: DailyShift?
    let store: Store
    let hourWidth: CGFloat

    @EnvironmentObject var firestoreVM: AppFirestoreVM

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            if let _ = dailyShift {
                ForEach(dailyShift!.staffShifts.indices, id: \.self) { index in
                    StaffShiftRow(
                        staff: Binding(
                            get: { dailyShift!.staffShifts[index] },
                            set: { newValue in
                                dailyShift!.staffShifts[index] = newValue
                                saveAndShareShift()
                            }
                        ),
                        hourWidth: hourWidth,
                        dailyShift: $dailyShift,
                        isAdmin: session.isAdmin
                    )
                }
            }
        }
        .onAppear {
            loadLocalShift()
            listenFirestoreShifts()
        }
    }

    // MARK: - ローカル保存
    private func saveAndShareShift() {
        guard let shift = dailyShift else { return }

        // ローカル保存
        let url = getShiftFileURL(for: shift.date)
        if let data = try? JSONEncoder().encode(shift) {
            try? data.write(to: url)
        }

        // Firestore
        firestoreVM.sendShiftToFirestore(dailyShift: shift)
    }

    private func loadLocalShift() {
        guard let date = dailyShift?.date,
              let loaded = loadShiftFromFile(date: date) else { return }
        dailyShift = loaded
    }

    private func getShiftFileURL(for date: Date) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let fileName = "shift_\(f.string(from: date)).json"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(fileName)
    }

    // MARK: - Firestore 受信
    private func listenFirestoreShifts() {
        Firestore.firestore()
            .collection("shifts")
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                if snapshot.metadata.hasPendingWrites { return }

                let shifts = snapshot.documents.compactMap {
                    try? $0.data(as: FirestoreShiftData.self).mapToDailyShift()
                }

                guard let date = dailyShift?.date else { return }

                if let matched = shifts.first(where: {
                    Calendar.current.isDate($0.date, inSameDayAs: date)
                }) {
                    DispatchQueue.main.async {
                        dailyShift = matched
                    }
                }
            }
    }
}

// --- StaffShiftRow（時間入力 → グリッド反映・半角強制 + 保存 + 同曜日反映 + 7日制限） ---
struct StaffShiftRow: View {

    @Binding var staff: StaffShift
    let hourWidth: CGFloat
    @Binding var dailyShift: DailyShift?
    
    let isAdmin: Bool   // ✅ 追加：管理者フラグ

    @State private var rangeText: String = ""

    // 名前列の幅（左余白1cm分を追加）
    private let nameColumnWidth: CGFloat = 90 + 38

    // ✅ 今日＋7日以降のみ編集可能
    private var canEdit: Bool {
        guard let shiftDate = dailyShift?.date else { return false }

        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: shiftDate)

        guard let limitDate = Calendar.current.date(byAdding: .day, value: 7, to: today) else {
            return false
        }

        return isAdmin || target >= limitDate   // ✅ 管理者は常に true
   
    }

    var body: some View {
        HStack(spacing: 0) {

            // ✅ 名前欄（7日制限）
            TextField("名前", text: $staff.staffName)
                .textFieldStyle(.roundedBorder)
                .frame(width: nameColumnWidth, height: 36, alignment: .leading)
                .onChange(of: staff.staffName) {
                    applyRange()
                }
                .disabled(!canEdit)          // ✅ ロック
                .opacity(canEdit ? 1 : 0.4)  // ✅ グレー表示

            // ✅ 時間入力（7日制限）
            TextField("0-8", text: $rangeText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .frame(width: 60, height: 36)
                .onSubmit { applyRange() }
                .onChange(of: rangeText) {
                    rangeText = normalizeRangeText(rangeText)
                    applyRange()
                }
                .disabled(!canEdit)          // ✅ ロック
                .opacity(canEdit ? 1 : 0.4)  // ✅ グレー表示

            // 24時間グリッド
            ZStack(alignment: .leading) {

                // ✅ 通常の細いグリッド
                HStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { _ in
                        Rectangle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                            .frame(width: hourWidth, height: 36)
                    }
                }

                // ✅ ★ 7時と8時の間の縦線
                Rectangle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 2, height: 36)
                    .offset(x: hourWidth * 8)

                // ✅ ★ 16時と17時の間の縦線
                Rectangle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 2, height: 36)
                    .offset(x: hourWidth * 17)

                // ✅ シフトの青いバー
                ForEach(staff.ranges.indices, id: \.self) { i in
                    let range = staff.ranges[i]
                    let start = max(0, min(23, range.start))
                    let end   = max(start + 1, min(24, range.end))

                    Rectangle()
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: CGFloat(end - start) * hourWidth, height: 36)
                        .offset(x: CGFloat(start) * hourWidth)
                }
            }
        }
    }

    // --- 以下 applyRange や保存処理は元のまま（※7日制限ガード追加） ---
    private func applyRange() {

        // ✅ 7日未満は保存禁止
        if !canEdit { return }

        let cleaned = rangeText
        let parts = cleaned.split(separator: "-")
        staff.ranges = []

        guard
            parts.count == 2,
            let start = Int(parts[0].trimmingCharacters(in: .whitespaces)),
            let end   = Int(parts[1].trimmingCharacters(in: .whitespaces)),
            start >= 0, end <= 24, start < end
        else { return }

        staff.ranges = [ShiftRange(start: start, end: end)]
        saveShiftAndCopyToSameWeekday()
    }

    private func saveShiftAndCopyToSameWeekday() {
        guard let shift = dailyShift else { return }

        let currentWeekday = Calendar.current.component(.weekday, from: shift.date)
        let allDates = getFutureDates()
        let staffIndex = shift.staffShifts.firstIndex(where: { $0.id == staff.id }) ?? 0

        for date in allDates {
            if Calendar.current.component(.weekday, from: date) == currentWeekday {
                var newShift = shift
                newShift.date = date
                newShift.staffShifts[staffIndex] = staff
                saveShiftToFile(newShift)
            }
        }
    }

    private func saveShiftToFile(_ shift: DailyShift) {
        let url = getShiftFileURL(for: shift.date)
        if let data = try? JSONEncoder().encode(shift) {
            try? data.write(to: url)
        }
    }

    private func getShiftFileURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "shift_\(formatter.string(from: date)).json"
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return folder.appendingPathComponent(fileName)
    }

    private func normalizeRangeText(_ s: String) -> String {
        var out = ""
        for ch in s {
            let scalar = ch.unicodeScalars.first!.value
            if (0xFF10...0xFF19).contains(scalar) { out.append(String(scalar - 0xFF10)); continue }
            if ch >= "0" && ch <= "9" { out.append(ch); continue }
            if ["ー","−","—","－","-"].contains(ch) { out.append("-"); continue }
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out
    }

    private func getFutureDates(days: Int = 30) -> [Date] {
        var dates: [Date] = []
        let today = Date()
        for i in 0..<days {
            if let date = Calendar.current.date(byAdding: .day, value: i, to: today) {
                dates.append(date)
            }
        }
        return dates
    }
}

struct UncoveredDateListView: View {

    let store: Store
    let onSelect: (Date) -> Void
    @State private var dates: [Date] = []
    private let offsetAmount: CGFloat = 18

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {

                VStack(alignment: .center, spacing: 10){

                    Text("シフト不足日")
                        .font(.headline)
                        .id("TOP")
                        .padding(.bottom, 6)
                        .offset(y: 15)

                    if dates.isEmpty {
                        Text("すべてフルカバーです ✅")
                            .foregroundColor(.green)
                    } else {
                        ForEach(dates, id: \.self) { date in
                            Button {
                                onSelect(date)
                            } label: {
                                Text(formattedDate(date))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)   // ✅ ★ここが重要（横padding削除）
                .offset(y: offsetAmount)
            }
            .onAppear {
                dates = getUncoveredDatesNextTwoWeeks(storeName: store.name)

                DispatchQueue.main.async {
                    proxy.scrollTo("TOP", anchor: .top)
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d（EEE）"
        return f.string(from: date)
    }
}


func calculateWorkingMinutes(ranges: [ShiftRange]) -> Int {
    var minutes = 0
    for r in ranges {
        minutes += (r.end - r.start) * 60
    }
    return minutes
}

func adjustedMinutes(rawMinutes: Int) -> Int {
    if rawMinutes >= 8 * 60 {
        return rawMinutes - 60
    } else if rawMinutes >= 6 * 60 {
        return rawMinutes - 45
    } else {
        return rawMinutes
    }
}

func isKatakanaOnly(_ text: String) -> Bool {
    let pattern = "^[ァ-ンヴー]+$"
    return text.range(of: pattern, options: .regularExpression) != nil
}

func currentSaturdayToFriday() -> (start: Date, end: Date) {
    let cal = Calendar.current
    let today = Date()
    let weekday = cal.component(.weekday, from: today)

    // 土曜 = 7
    let daysFromSaturday = (weekday + 6) % 7
    let saturday = cal.date(byAdding: .day, value: -daysFromSaturday, to: today)!
    let friday = cal.date(byAdding: .day, value: 6, to: saturday)!

    return (saturday, friday)
}

func loadWeeklyStaffSummary(storeName: String) -> [(String, Int)] {

    let cal = Calendar.current
    let range = currentSaturdayToFriday()
    var result: [String: Int] = [:]

    var date = range.start
    while date <= range.end {

        if let shift = loadShiftFromFile(date: date),
           shift.storeName == storeName {

            for staff in shift.staffShifts {

                guard isKatakanaOnly(staff.staffName) else { continue }

                let raw = calculateWorkingMinutes(ranges: staff.ranges)
                let adjusted = adjustedMinutes(rawMinutes: raw)

                result[staff.staffName, default: 0] += adjusted
            }
        }

        date = cal.date(byAdding: .day, value: 1, to: date)!
    }

    return result.map { ($0.key, $0.value) }
        .sorted { $0.0 < $1.0 }
}

struct WeeklyStaffSummaryView: View {

    let store: Store
    @State private var data: [(String, Int)] = []

    private var periodText: String {
        let range = currentSaturdayToFriday()
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return "\(f.string(from: range.start))（土）〜\(f.string(from: range.end))（金）"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                Text("勤務時間集計")
                    .font(.headline)

                Text("期間：\(periodText)")
                    .font(.caption)
                    .foregroundColor(.gray)

                Divider()

                ForEach(data, id: \.0) { name, minutes in
                    let h = minutes / 60
                    let m = minutes % 60

                    HStack {
                        Text(name)
                            .frame(width: 120, alignment: .leading)

                        Spacer()

                        Text("\(h)時間\(m)分")
                            .bold()
                    }
                }
            }
            .padding()
        }
        .onAppear {
            data = loadWeeklyStaffSummary(storeName: store.name)
        }
    }
}


func generateWeeklyShiftPDFWithGanttAndTotal(for dailyShift: DailyShift) -> PDFDocument? {
    
    // PDF用データ
    let pdfData = NSMutableData()
    
    // A4横 72dpi換算
    let pageWidth: CGFloat = 842
    let pageHeight: CGFloat = 595
    let margin: CGFloat = 20
    let rowHeight: CGFloat = 30
    let headerHeight: CGFloat = 40
    let nameColumnWidth: CGFloat = 120
    let totalColumnWidth: CGFloat = 80
    let hourWidth: CGFloat = (pageWidth - margin * 2 - nameColumnWidth - totalColumnWidth) / 24  // 24時間分幅
    
    let font = UIFont.systemFont(ofSize: 12)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .left
    let textAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .paragraphStyle: paragraphStyle
    ]
    
    let cal = Calendar.current
    // 月曜〜日曜
    let weekday = cal.component(.weekday, from: dailyShift.date)
    let daysFromMonday = (weekday + 5) % 7
    let startOfWeek = cal.date(byAdding: .day, value: -daysFromMonday, to: dailyShift.date)!
    let weekDates = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: startOfWeek) }
    
    // PDFコンテキスト開始
    UIGraphicsBeginPDFContextToData(pdfData, CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), nil)
    UIGraphicsBeginPDFPage()
    guard let context = UIGraphicsGetCurrentContext() else { return nil }
    
    var yOffset: CGFloat = margin
    
    // --- タイトル ---
    let title = "シフト一覧（週）"
    title.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
    yOffset += headerHeight / 2
    
    // --- 日付ヘッダー ---
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "M/d（EEE）"
    
    var xOffset: CGFloat = margin + nameColumnWidth
    for date in weekDates {
        let dateStr = dateFormatter.string(from: date)
        dateStr.draw(at: CGPoint(x: xOffset, y: yOffset), withAttributes: textAttributes)
        xOffset += hourWidth * 24
    }
    
    // 右端に「合計時間」ヘッダー
    let totalHeaderX = margin + nameColumnWidth + hourWidth * 24 * 7 + 5
    "合計時間".draw(at: CGPoint(x: totalHeaderX, y: yOffset), withAttributes: textAttributes)
    
    yOffset += headerHeight / 2
    
    // --- スタッフ行 ---
    for staff in dailyShift.staffShifts {
        if staff.staffName.trimmingCharacters(in: .whitespaces).isEmpty { continue }
        
        // スタッフ名列
        staff.staffName.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
        
        var totalMinutes = 0
        xOffset = margin + nameColumnWidth
        for date in weekDates {
            if let shift = loadShiftFromFile(date: date),
               let staffForDate = shift.staffShifts.first(where: { $0.id == staff.id }) {
                
                for range in staffForDate.ranges {
                    let startX = xOffset + CGFloat(range.start) * hourWidth
                    let width = CGFloat(range.end - range.start) * hourWidth
                    let rect = CGRect(x: startX, y: yOffset, width: width, height: rowHeight * 0.6)
                    
                    context.setFillColor(UIColor.systemBlue.cgColor)
                    context.fill(rect)
                    
                    totalMinutes += (range.end - range.start) * 60
                }
            }
            xOffset += hourWidth * 24
        }
        
        // --- 右端に週合計時間 ---
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        let totalStr = "\(h)時間\(m)分"
        totalStr.draw(at: CGPoint(x: totalHeaderX, y: yOffset), withAttributes: textAttributes)
        
        yOffset += rowHeight
        if yOffset > pageHeight - margin {
            UIGraphicsBeginPDFPage()
            yOffset = margin
        }
    }
    
    // PDFコンテキスト終了
    UIGraphicsEndPDFContext()
    
    // PDFDocumentを作成して返す
    return PDFDocument(data: pdfData as Data)
}

struct PDFPreviewSheet: View {
    let pdfDocument: PDFDocument

    var body: some View {
        VStack(spacing: 0) {
            PDFKitView(pdfDocument: pdfDocument)
                .edgesIgnoringSafeArea(.all)

            Button("印刷") {
                let printController = UIPrintInteractionController.shared
                let printInfo = UIPrintInfo.printInfo()
                printInfo.outputType = .general
                printInfo.jobName = "シフト一覧"
                printInfo.orientation = .landscape
                printController.printInfo = printInfo
                printController.printingItem = pdfDocument.dataRepresentation()
                printController.present(animated: true)
            }
            .padding()
            .background(Color(.systemGray6))
        }
    }
}

// PDFKit を SwiftUI にラップする簡易ビュー
struct PDFKitView: UIViewRepresentable {
    let pdfDocument: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = pdfDocument
        pdfView.autoScales = true
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
