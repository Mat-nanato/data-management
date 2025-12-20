import SwiftUI
import PhotosUI
import CoreLocation
import FirebaseCore
import FirebaseFirestore
import Combine
import BackgroundTasks


enum AppOrientation {
    static var lock: UIInterfaceOrientationMask = .portrait
}

// AppDelegate（必要なら残す）
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .all
    }
}

@main
struct MyApp: App {
    // 🔥 全アプリで共有する Firestore VM
    @StateObject var appVM = AppFirestoreVM()
    @StateObject var photoVM = PhotoVM()   // ← 追加

    init() {
        FirebaseApp.configure()
        registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            DoorView()
                .environmentObject(appVM)
                .environmentObject(photoVM)   // ← 追加
        }
    }
}

    // MARK: - バックグラウンドタスク登録
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.yourapp.weatherRefresh",
            using: nil
        ) { task in
            handleWeatherRefreshTask(task: task as! BGAppRefreshTask)
        }
    }

    // MARK: - タスク実行処理
    func handleWeatherRefreshTask(task: BGAppRefreshTask) {
        // ここで CSV/JSON 取得や保存処理を行う
        print("Weather refresh task executed")

        // 次回タスクをスケジュール
        scheduleNextWeatherRefresh()

        task.setTaskCompleted(success: true)
    }

    // MARK: - 次回タスクのスケジュール
    func scheduleNextWeatherRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.yourapp.weatherRefresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60*60) // 1時間後
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("BGTaskScheduler submit error: \(error)")
        }
    }


// MARK: - メイン画面
struct DoorView: View {
    @State private var navigateToStoreSelect = false
    @State private var navigateToShiftEditor = false
    @State private var selectedStoreForShift: Store? = nil
    @State private var latestPhotoImage: UIImage? = nil
    @State private var latestPhotoStore: String? = nil
    @State private var navigateToHistory = false
    @State private var navigateToPhotoFolder = false
    @State private var navigateToChat = false
    @State private var pastMessages: [PastChatMsg] = []  // 型を PastChatMsg に変更
    @StateObject private var fm = FamilyMartInfoViewModel()
    @State private var bottomCards = ["東勝山", "上杉", "木町", "安養寺", "利府", "電力", "中山"]
    @State private var productTexts: [String] = [] // UI に反映される
    @State private var sharedMessages: [Message] = [
        Message(text: "お疲れ様です！", isMyMessage: false),
        Message(text: "最後、名前を入れてください", isMyMessage: true),
        Message(text: "日報数値は自動反映されます", isMyMessage: false)
    ]
    
    // MARK: - POPフォーム関連
    @State private var showPOPForm = false
    @State private var popProductName = ""
    @State private var popPrice = ""
    @State private var popAdditionalImage: UIImage? = nil
    @State private var generatedPOPImage: UIImage? = nil
    @State private var isGeneratingPOP = false
    @State private var showPOPImage = false
    @State private var showImagePicker = false
    @State private var popImageMemo: String = ""
    @State private var selectedOrientation: PaperOrientation = .portrait
    
    // MARK: - メガホンフォーム関連
    @State private var showMegaphoneForm = false   // ← 新規追加
    @State private var megaphoneProductName = ""
    @State private var megaphonePrice = ""
    
    @EnvironmentObject var appVM: AppFirestoreVM

    @MainActor
    func generatePOPButtonTapped() async {
        isGeneratingPOP = true
        defer { isGeneratingPOP = false }

        let base64Image = popAdditionalImage?.jpegData(compressionQuality: 0.8)?.base64EncodedString()
        let data = POPData(
            productName: popProductName,
            price: popPrice,
            memo: popImageMemo,
            additionalImageBase64: base64Image,
            paperOrientation: selectedOrientation // ← Pickerで選択した値を渡す
        )


        do {
            // 🔥 Cloudflare Worker から OpenAI APIキーを取得
            let key = try await fetchOpenAIKeyFromWorker()

            // 🔥 取得したキーで POP 画像生成
            let (image, _) = try await generatePOPImage(data: data, openAIKey: key)

            generatedPOPImage = image
            showPOPImage = true
            
        } catch {
            print("POP生成失敗:", error)
        }
    }


    struct CoinButton: View {
        let icon: String?
        let title: String?
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [Color.yellow, Color.orange]),
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: 70, height: 70)
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 2, y: 2)
                    
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundColor(.white)
                            .font(.system(size: 32, weight: .bold))
                    } else if let title = title {
                        Text(title)
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .padding(.leading, 20)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                
                // 背景
                Image("Image")
                    .resizable()
                    .scaledToFill()
                    .frame(width: UIScreen.main.bounds.width / 2,
                           height: UIScreen.main.bounds.height / 2)
                    .clipped()
                    .position(x: UIScreen.main.bounds.width / 2,
                              y: UIScreen.main.bounds.height / 2 + 110)
                    .allowsHitTesting(false)
                
                // 左黒帯
                Rectangle()
                    .fill(Color.black)
                    .frame(width: UIScreen.main.bounds.width / 4)
                    .edgesIgnoringSafeArea(.all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                
                VStack {
                    // 🔥 上部カード
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ファミマ最新情報")
                            .font(.headline)
                            .padding(.top, 10)
                        
                        ScrollView(.vertical, showsIndicators: true) {
                            HStack {
                                Spacer().frame(width: 28)   // ✅ 物理的に左に空白を作る（絶対ズレる）
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    if fm.isLoading {
                                        ProgressView()
                                    } else {
                                        Text(fm.latestInfo)
                                    }
                                }
                                
                                Spacer()
                            }
                        }
                        .frame(height: 170)
                        
                    }
                    
                    .frame(width: UIScreen.main.bounds.width / 1.5)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    .padding(.top, 50)
                    .offset(x: 45)
                    
                    // 右側店舗カード
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            ForEach(bottomCards, id: \.self) { card in
                                NavigationLink(
                                    destination: ContentView(storeName: card, chatMessages: $sharedMessages)
                                        .environmentObject(appVM)   // ← ここを追加
                                ) {
                                    Text(card)
                                        .frame(width: 120, height: 60)
                                        .background(Color.white.opacity(0.8))
                                        .cornerRadius(10)
                                        .shadow(radius: 2)
                                }
                            }

                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.bottom, 50)
                }
                
                // POPボタンだけ独立
                Button(action: { showPOPForm = true }) {
                    Text("POP")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 70)
                        .background(Circle().fill(Color.red))
                        .shadow(radius: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading,28) // ← 左に寄せる量
                .padding(.top, 20)     // ← 縦位置調整

               
                // 左側ボタン群（POP以外）
                VStack(spacing: 20) {
                    SideButton(icon: "calendar", title: nil, backgroundColor: .orange) {
                        navigateToStoreSelect = true
                    }

                    SideButton(icon: "message.fill", title: nil, backgroundColor: .blue) {
                        navigateToChat = true
                    }

                    SideButton(icon: "megaphone.fill", title: nil, backgroundColor: .green) {
                        showMegaphoneForm = true
                    }
                    .padding(.leading, -1) // ← 小さくマイナスにして少し左に


                    SideButton(icon: "photo.fill", title: nil, backgroundColor: .purple) {
                        navigateToPhotoFolder = true
                    }

                    CoinButton(icon: "bitcoinsign.circle.fill", title: nil) {
                        let manager = CLLocationManager()
                        manager.requestWhenInUseAuthorization()
                        if let url = URL(string: "https://cointogether-map.com") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading) // ← 左寄せ
                    .offset(x: 4) // ← さらに左に微調整


                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 130)
                .padding(.leading, 5)
                
                // ★ 最新写真（正しい場所：ZStack の最上層）
                if let img = latestPhotoImage {
                    ZStack(alignment: .bottomLeading) {
                        
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 140, height: 140)
                            .clipped()
                            .cornerRadius(10)
                        
                        if let store = latestPhotoStore {
                            Text(store)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(6)
                                .padding(5)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
                }
                
            } // ZStack
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $navigateToChat) {
                ChatViewWrapper(messages: $sharedMessages)
            }
            .navigationDestination(isPresented: $navigateToPhotoFolder) {
                PhotoFolderView(sharedMessages: $sharedMessages)
            }
            .navigationDestination(isPresented: $navigateToStoreSelect) {
                StoreSelectView(stores: bottomCards.map { Store(name: $0, baseShifts: [ShiftRange(start: 9, end: 18)]) })
            }
            .navigationDestination(isPresented: $navigateToShiftEditor) {
                if let store = selectedStoreForShift {
                    LandscapeView {
                        ShiftEditorView(store: store)
                    }
                }
            }

            .onAppear {
                fm.loadLatestInfo()
                
                let storesList = bottomCards
                if let info = loadLatestPhotoInfo(stores: storesList) {
                    latestPhotoImage = info.image
                    latestPhotoStore = info.store
                } else {
                    latestPhotoImage = nil
                    latestPhotoStore = nil
                }
            }
            
        } // NavigationStack

        // POPフォーム用シート
        .sheet(isPresented: $showPOPForm) {
            VStack(spacing: 20) {
                if showPOPImage, let img = generatedPOPImage {
                    // 生成されたPOP表示
                    VStack {
                        Text("生成されたPOP").font(.headline)

                        ScrollView([.vertical, .horizontal]) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 600)
                        }

                        Button(action: {
                            showPOPForm = false
                            showPOPImage = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                generatePDF(from: img, orientation: selectedOrientation)
                            }
                        }) {
                            HStack {
                                Image(systemName: "doc.richtext")
                                Text("A4 PDFとして出力する").bold()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.top, 20)

                        Button("閉じる") {
                            showPOPImage = false
                            showPOPForm = false
                            showImagePicker = false
                        }
                    }
                    .padding()
                    
                } else {
                    // POP入力フォーム
                    VStack(spacing: 20) {
                        Text("POP作成フォーム").font(.headline)

                        TextField("商品名", text: $popProductName)
                            .textFieldStyle(.roundedBorder)
                        TextField("値段（税込）", text: $popPrice)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("POP作成イメージ").font(.subheadline).foregroundColor(.gray)
                            TextEditor(text: $popImageMemo)
                                .frame(height: 200)
                                .padding(6)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.4), lineWidth: 1))

                            VStack(alignment: .leading) {
                                Text("用紙の向き").font(.subheadline)
                                Picker("A4用紙方向", selection: $selectedOrientation) {
                                    ForEach(PaperOrientation.allCases) { orientation in
                                        Text(orientation.rawValue).tag(orientation)
                                    }
                                }
                            }

                            if let selectedImage = popAdditionalImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 150)
                                    .cornerRadius(10)
                                    .shadow(radius: 3)
                            }
                        }

                        Button("画像を選ぶ（無くても可）") {
                            showImagePicker = true
                        }
                        .sheet(isPresented: $showImagePicker) {
                            POPPhotoPicker(image: $popAdditionalImage, showPOPForm: $showPOPForm)
                                .ignoresSafeArea()
                        }

                        if isGeneratingPOP {
                            ProgressView("POP生成中...")
                        }

                        Button("POP生成") {
                            Task {
                                isGeneratingPOP = true
                                defer { isGeneratingPOP = false }

                                let base64Image = popAdditionalImage?.jpegData(compressionQuality: 0.8)?.base64EncodedString()
                                let data = POPData(
                                    productName: popProductName,
                                    price: popPrice,
                                    memo: popImageMemo,
                                    additionalImageBase64: base64Image,
                                    paperOrientation: selectedOrientation
                                )

                                do {
                                    let key = try await fetchOpenAIKeyFromWorker()
                                    let (image, _) = try await generatePOPImage(data: data, openAIKey: key)
                                    generatedPOPImage = image
                                    showPOPImage = true
                                } catch {
                                    print("POP生成失敗:", error)
                                    generatedPOPImage = generateDummyPOP()
                                    showPOPImage = true
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .background(Color.white)
        }

        // メガホンフォーム用シート
        .sheet(isPresented: $showMegaphoneForm) {
            MegaphoneFormView(
                productName: $megaphoneProductName,
                price: $megaphonePrice
            )
        }
    }
    
    func generateDummyPOP() -> UIImage {
        let size = CGSize(width: 600, height: 800)
        UIGraphicsBeginImageContextWithOptions(size, true, 0)
        defer { UIGraphicsEndImageContext() }

        // 背景色
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        // 「失敗」文字
        let text = "失敗"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 60),
            .foregroundColor: UIColor.red
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width)/2,
            y: (size.height - textSize.height)/2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)

        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    func generatePDF(from image: UIImage, orientation: PaperOrientation) {
        // A4 サイズ（pt）
        let a4Size: CGSize = orientation == .portrait
            ? CGSize(width: 595.2, height: 841.8)     // 縦
            : CGSize(width: 841.8, height: 595.2)     // 横
        
        // PDF を保存する一時ファイル
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pop.pdf")

        // PDF 作成
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: a4Size))

        do {
            try pdfRenderer.writePDF(to: url) { ctx in
                ctx.beginPage()

                // 画像を A4 にフィットさせて描画
                let imgSize = image.size
                let scale = min(a4Size.width / imgSize.width, a4Size.height / imgSize.height)
                let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
                let drawOrigin = CGPoint(
                    x: (a4Size.width - drawSize.width) / 2,
                    y: (a4Size.height - drawSize.height) / 2
                )

                image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
            }

            // PDF を共有する UI を表示
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)

            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first?
                .rootViewController?
                .present(av, animated: true)

        } catch {
            print("PDF生成失敗:", error)
        }
    }

    func loadPastData(from jsonArray: [[String: Any]]) {
        var temp: [PastChatMsg] = []
        for item in jsonArray {
            guard let dateStr = item["date"] as? String,
                  let name = item["name"] as? String,
                  let price = item["price"] as? Double,
                  let date = ISO8601DateFormatter().date(from: dateStr) else { continue }

            let text = "商品: \(name)\n価格: \(price)"
            let message = PastChatMsg(
                id: Int(date.timeIntervalSince1970),
                text: text,
                isMyMessage: false,
                date: date
            )
            temp.append(message)
        }
        // 日付順にソート
        pastMessages = temp.sorted { $0.date < $1.date }
    }
}

struct StoreSelectView: View {
    let stores: [Store]
    @State private var navigateToShiftEditor = false
    @State private var selectedStore: Store? = nil

    var body: some View {
        List(stores) { store in
            Button(store.name) {
                selectedStore = store
                navigateToShiftEditor = true
            }
        }
        .navigationTitle("店舗を選択")
        .navigationDestination(isPresented: $navigateToShiftEditor) {
            if let store = selectedStore {
                ShiftEditorView(store: store)
            }
        }
    }
}

struct SideButton: View {
    let icon: String?
    let title: String?
    let backgroundColor: Color
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                if let icon = icon, !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 28))                // ← アイコン大きく
                        .foregroundColor(.white)
                        .padding(20)                            // ← 余白大きく
                        .background(backgroundColor)
                        .clipShape(Circle())
                        .shadow(radius: 5)                      // ← 少し強調
                } else if let title = title {
                    Text(title)
                        .font(.system(size: 22, weight: .bold)) // ← 文字サイズアップ
                        .foregroundColor(.white)
                        .padding(.vertical, 18)                 // ← 高さ増し
                        .padding(.horizontal, 28)               // ← 横幅増し
                        .background(backgroundColor)
                        .cornerRadius(14)
                        .shadow(radius: 5)
                }
            }
            .padding(.leading, 20)
            Spacer()
        }
        .padding(.bottom, 20)   // ← ボタン同士の間隔も少し広げた
    }
}

    // MARK: - 今日の日付
    func getTodayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日（E）"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: Date())
    }



// MARK: - 左側ボタンコンポーネント
struct LeftButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 3)
            }
            .padding(.leading, 20)
            Spacer()
        }
        .padding(.bottom, 15)
    }
}

// MARK: - 写真フォルダ選択画面
struct PhotoFolderView: View {
    let stores = ["東勝山", "上杉", "木町", "安養寺", "利府", "電力", "中山"]

    @Binding var sharedMessages: [Message] // ← 共有チャット用

    var body: some View {
        List(stores, id: \.self) { store in
            NavigationLink(destination: StorePhotoView(storeName: store)) { // 日付は不要
                Text(store)
                    .padding()
            }
        }
        .navigationTitle("店舗フォルダ")
    }
}

// MARK: - メッセージ構造体（ユニーク名）
struct ChatMsg: Identifiable {
    let id: Int
    let text: String
    let isMyMessage: Bool
}

// 過去情報用の構造体
struct PastChatMsg: Identifiable {
let id: Int
let text: String
let isMyMessage: Bool
let date: Date
}

// MARK: - 吹き出しUI（ユニーク名）
struct ChatMsgRow: View {
    let message: ChatMsg

    var body: some View {
        HStack {
            if message.isMyMessage {
                Spacer()
                Text(message.text)
                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                    .frame(maxWidth: 250, alignment: .trailing)
            } else {
                Text(message.text)
                    .padding(10)
                    .background(Color(UIColor.systemGray4))
                    .cornerRadius(15)
                    .frame(maxWidth: 250, alignment: .leading)
                Spacer()
            }
        }
        .padding(.horizontal, 4)
        .id(message.id)
    }
}
/// Documents/<store>/<yyyy-MM-dd>/* を全店舗走査して、最も新しいファイルを返す
private func loadLatestPhotoInfo(stores: [String]) -> (image: UIImage, store: String)? {
    let fm = FileManager.default
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }

    var newestURL: URL?
    var newestDate: Date?

    for store in stores {
        let storeFolder = docs.appendingPathComponent(store)
        guard fm.fileExists(atPath: storeFolder.path),
              let dateFolders = try? fm.contentsOfDirectory(at: storeFolder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
        else { continue }

        for dateFolder in dateFolders {
            guard let files = try? fm.contentsOfDirectory(at: dateFolder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { continue }

            for file in files {
                let ext = file.pathExtension.lowercased()
                guard ["jpg","jpeg","png"].contains(ext) else { continue }

                if let attrs = try? fm.attributesOfItem(atPath: file.path),
                   let mod = attrs[.modificationDate] as? Date {
                    if newestDate == nil || mod > newestDate! {
                        newestDate = mod
                        newestURL = file
                    }
                } else {
                    if let vals = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                       let mod = vals.contentModificationDate {
                        if newestDate == nil || mod > newestDate! {
                            newestDate = mod
                            newestURL = file
                        }
                    }
                }
            }
        }
    }

    // 🔽🔽🔽 ← ここを追加しないと警告が出る
    if let url = newestURL,
       let data = try? Data(contentsOf: url),
       let img = UIImage(data: data) {

        var matchedStore: String? = nil
        for store in stores {
            if url.path.contains("/\(store)/") {
                matchedStore = store
                break
            }
        }

        return (image: img, store: matchedStore ?? "不明")
    }

    return nil
}


struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first?.itemProvider,
                  item.canLoadObject(ofClass: UIImage.self) else { return }

            item.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    self.parent.selectedImage = object as? UIImage
                }
            }
        }
    }
}

struct POPPhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var showPOPForm: Bool

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

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: POPPhotoPicker
        init(_ parent: POPPhotoPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            picker.dismiss(animated: true)

        }
    }
}

// MARK: - Worker は APIキーを隠すだけ
let popWorkerURL = URL(string: "https://familymart-worker.app-lab-nanato.workers.dev/")!

struct POPData: Codable {
    var productName: String
    var price: String
    var memo: String
    var additionalImageBase64: String?
    var paperOrientation: PaperOrientation // ← 追加
}

// MARK: - Swift 側での生成レスポンス
struct OpenAIImageResponse: Decodable {
    struct DataItem: Decodable {
        let b64_json: String
    }
    let data: [DataItem]      // ← optional にするな
}


struct WorkerTextResponse: Decodable {
    let text: String
}

// MARK: - Worker への送信（APIキー隠し用）
@MainActor
func sendPOPDataToWorker(data: POPData) async throws -> String {
    let jsonData = try JSONEncoder().encode(data)
    var request = URLRequest(url: popWorkerURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 300
    request.httpBody = jsonData

    let (responseData, _) = try await URLSession.shared.data(for: request)
    print(String(data: responseData, encoding: .utf8) ?? "empty")

    
    // JSON のエラー確認
    if let dict = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any],
       let errorMsg = dict["error"] as? String {
        throw NSError(domain: "POPGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
    }

    // Worker が返す JSON 形式に合わせてデコード
    struct WorkerTextResponse: Decodable {
        let text: String
    }

    let decoded = try JSONDecoder().decode(WorkerTextResponse.self, from: responseData)
    return decoded.text
}


// MARK: - Swift 側で直接画像生成
@MainActor
func generatePOPImage(data: POPData, openAIKey: String) async throws -> (UIImage, String) {

    // 縦横情報をプロンプトに追加
    let orientationText = data.paperOrientation == .portrait ? "縦向き" : "横向き"

    let prompt = """
    商品名: \(data.productName)
    値段: \(data.price)
    メモ: \(data.memo)
    参考画像あり: \(data.additionalImageBase64 != nil ? "はい" : "なし")
    用紙の向き: \(orientationText)
    イラスト風のPOPを生成してください。
    """

    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    // A4向きに応じて size を変更
    let size: String
    switch data.paperOrientation {
    case .portrait:
        size = "768x1024"  // 縦長
    case .landscape:
        size = "1024x768"  // 横長
    }

    let body: [String: Any] = [
        "model": "gpt-image-1",
        "prompt": prompt,
        "size": size
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (responseData, _) = try await URLSession.shared.data(for: request)

    if let responseString = String(data: responseData, encoding: .utf8) {
        print("OpenAI 画像生成レスポンス:\n\(responseString)")
    }

    struct OpenAIImageResponse: Decodable {
        struct DataItem: Decodable {
            let url: String?
        }
        let data: [DataItem]?
        let error: OpenAIError?
        
        struct OpenAIError: Decodable {
            let message: String
        }
    }

    let decoded = try JSONDecoder().decode(OpenAIImageResponse.self, from: responseData)

    if let err = decoded.error {
        throw NSError(domain: "POPGenerator", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: err.message])
    }

    guard let urlString = decoded.data?.first?.url,
          let url = URL(string: urlString) else {
        throw NSError(domain: "POPGenerator", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "画像URLが取得できませんでした"])
    }

    let (imageData, _) = try await URLSession.shared.data(from: url)
    guard let uiImage = UIImage(data: imageData) else {
        throw NSError(domain: "POPGenerator", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "画像ダウンロード失敗"])
    }

    return (uiImage, prompt)
}

// MARK: - SwiftUI View

enum PaperOrientation: String, Codable, CaseIterable, Identifiable {
    case portrait = "縦"
    case landscape = "横"
    
    var id: String { self.rawValue }
}

struct POPGeneratorView: View {
    @State private var productName = ""
    @State private var price = ""
    @State private var memo = ""
    @State private var additionalImage: UIImage? = nil
    
    @State private var generatedPOP: UIImage? = nil
    @State private var generatedPOPText: String = ""
    @State private var isGenerating = false
    @State private var showImagePicker = false
    
    // 追加: 用紙向き
    @State private var selectedOrientation: PaperOrientation = .portrait
    
    var body: some View {
        VStack(spacing: 20) {
            TextField("商品名", text: $productName)
                .textFieldStyle(.roundedBorder)
            
            TextField("値段", text: $price)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
            
            TextEditor(text: $memo)
                .frame(height: 150)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
            
            // 追加: A4用紙向き Picker
            VStack(alignment: .leading) {
                Text("用紙の向き")
                    .font(.subheadline)
                Picker("用紙の向き", selection: $selectedOrientation) {
                    ForEach(PaperOrientation.allCases) { orientation in
                        Text(orientation.rawValue).tag(orientation)
                    }
                }
                .pickerStyle(MenuPickerStyle()) // プルダウン形式
            }
            
            Button("画像を選ぶ") { showImagePicker = true }
                .sheet(isPresented: $showImagePicker) {
                    ImagePicker(selectedImage: $additionalImage)
                }
            
            if isGenerating {
                ProgressView("POP生成中...")
            }
            
            Button("POP生成") {
                Task {
                    await generatePOPAction()
                }
            }
            
            if let popImage = generatedPOP {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: popImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 600)
                }
            }
            
            Button(action: {
                generatePDF()
            }) {
                HStack {
                    Image(systemName: "doc.richtext")
                    Text("PDFを生成する")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.9))
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
            Spacer()
        }
        .padding()
    }
    
    func generatePOPAction() async {
        isGenerating = true
        defer { isGenerating = false }
        
        let base64Image = additionalImage?.jpegData(compressionQuality: 0.8)?.base64EncodedString()
        let data = POPData(
            productName: productName,
            price: price,
            memo: memo,
            additionalImageBase64: base64Image,
            paperOrientation: selectedOrientation
        )
        
        do {
            let key = try await fetchOpenAIKeyFromWorker()
            let (image, text) = try await generatePOPImage(data: data, openAIKey: key)
            generatedPOP = image
            generatedPOPText = text
        } catch {
            print("POP生成失敗:", error)
            // ダミーPOP生成
            generatedPOP = generateDummyPOP()
            generatedPOPText = "失敗"
        }
    }
    
    // MARK: - ダミーPOP生成
    func generateDummyPOP() -> UIImage {
        let size = CGSize(width: 600, height: 800)
        UIGraphicsBeginImageContextWithOptions(size, true, 0)
        defer { UIGraphicsEndImageContext() }
        
        // 背景色
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        
        // 「失敗」文字
        let text = "失敗"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 60),
            .foregroundColor: UIColor.red
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width)/2,
            y: (size.height - textSize.height)/2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
    
    // MARK: - PDF生成（安全版）
    func generatePDF() {
        guard let popImage = generatedPOP else {
            print("画像がまだ生成されていません")
            return
        }
        
        // A4サイズ（pt単位）
        let a4Portrait = CGSize(width: 595.2, height: 841.8)
        let a4Landscape = CGSize(width: 841.8, height: 595.2)
        let pdfSize = (selectedOrientation == .portrait) ? a4Portrait : a4Landscape
        let bounds = CGRect(origin: .zero, size: pdfSize)
        
        // 画像をA4に合わせて縮小
        let aspect = min(pdfSize.width / popImage.size.width,
                         pdfSize.height / popImage.size.height)
        let drawSize = CGSize(width: popImage.size.width * aspect,
                              height: popImage.size.height * aspect)
        let drawRect = CGRect(
            x: (pdfSize.width - drawSize.width) / 2,
            y: (pdfSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        
        do {
            let data = renderer.pdfData { context in
                context.beginPage()
                popImage.draw(in: drawRect)
            }
            
            // 一時ファイルに保存
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("POP_A4.pdf")
            try data.write(to: url)
            print("PDF 保存成功:", url)
            
            // メインスレッドで遅延表示して安全に UIActivityViewController を開く
            DispatchQueue.main.async {
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = scene.windows.first?.rootViewController {
                    let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    root.present(av, animated: true)
                }
            }
            
        } catch {
            print("PDF生成に失敗:", error)
        }
    }
}
// MARK: - ImagePicker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.selectedImage = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
        }
    }
}

@MainActor
func fetchOpenAIKeyFromWorker() async throws -> String {
    var request = URLRequest(url: popWorkerURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    request.httpBody = try JSONSerialization.data(
        withJSONObject: ["type": "get_key"]
    )

    let (data, _) = try await URLSession.shared.data(for: request)

    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let key = dict?["key"] as? String else {
        throw NSError(domain: "POPGenerator", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "APIキー取得失敗"])
    }
    return key
}


struct MegaphoneFormView: View {
    @Binding var productName: String
    @Binding var price: String
    @StateObject private var speaker = MegaphoneSpeaker()

    @State private var items: [(name: String, price: String)] = [
        ("", ""), ("", ""), ("", ""), ("", ""), ("", "")
    ]


    var body: some View {
        VStack(spacing: 16) {

            // タイトルは中央寄せ
            Text("声かけ用フォーム")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)

            // 入力欄
            ForEach(0..<items.count, id: \.self) { index in
                VStack(spacing: 8) {
                    TextField("商品名 \(index+1)", text: $items[index].name)
                        .textFieldStyle(.roundedBorder)

                    TextField("値段 \(index+1)", text: $items[index].price)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
            }

            // 読み上げ開始／停止
            Button(speaker.isSpeaking ? "読み上げ停止" : "読み上げ開始") {
                if speaker.isSpeaking {
                    speaker.stopSpeaking()
                } else {
                    Task {
                        // 空欄の項目を除外
                        let nonEmptyItems = items.filter { !$0.name.isEmpty && !$0.price.isEmpty }
                        await speaker.startSpeakingWithWorker(items: nonEmptyItems)
                    }
                }
            }

            .disabled(items.isEmpty)
            .padding()
            .background(speaker.isSpeaking ? Color.red : Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
            
            // インターバル説明テキスト
            Text("商品間の読み上げは３分のインターバルがあります")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.top, 4)
            
            Text("１商品から入力可能です")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.top, 4)
            
            Spacer()
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    class MegaphoneSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
        struct Item {
            let name: String
            let price: String
            var recommendation: String? = nil
        }

        @Published var isSpeaking = false
        private var items: [Item] = []
        private var index = 0
        private let synthesizer = AVSpeechSynthesizer()

        // Worker経由でおすすめ文を取得してから読み上げ
        func startSpeakingWithWorker(items: [(name: String, price: String)]) async {
            var aiItems: [Item] = []

            for item in items {
                let rec = await fetchAIRecommendation(for: item.name, price: item.price)
                aiItems.append(Item(name: item.name, price: item.price, recommendation: rec))
            }

            // メインスレッドでプロパティ更新
            DispatchQueue.main.async {
                self.items = aiItems
                self.index = 0
                self.isSpeaking = true
                self.synthesizer.delegate = self
                self.speakNext()
            }
        }


        func stopSpeaking() {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
        }

        private func speakNext() {
            guard index < items.count else {
                isSpeaking = false
                return
            }

            let item = items[index]
            let rec = item.recommendation ?? ""
            let utteranceText = "\(rec) \(item.name) \(item.price)円 \(rec)"
            let utterance = AVSpeechUtterance(string: utteranceText)
            utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
            synthesizer.speak(utterance)
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            index += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.speakNext()
            }
        }

        // 🔹 Worker経由でおすすめ文を取得
        private func fetchAIRecommendation(for name: String, price: String) async -> String {
            guard let url = URL(string: "https://my-worker.app-lab-nanato.workers.dev") else { return "" }

            let requestBody: [String: Any] = [
                "type": "recommendation",       // ← ここを追加
                "name": name,
                "price": price
            ]

            guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else { return "" }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = httpBody
            request.timeoutInterval = 60

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                struct WorkerResponse: Codable { let reply: String }
                let decoded = try JSONDecoder().decode(WorkerResponse.self, from: data)
                return decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                print("Worker呼び出しエラー:", error)
                return ""
            }
        }
    }
}


