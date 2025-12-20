import SwiftUI
import Firebase
import FirebaseFirestore

struct ChatView: View {
    @ObservedObject var vm: AppFirestoreVM        // ← ★ Firestore の VM を受け取る
    @State private var inputText: String = ""

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(vm.messages) { message in
                            MessageRow(message: message)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    withAnimation {
                        if let last = vm.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // 入力欄
            HStack {
                TextField("メッセージを入力", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                        .padding(8)
                }
                .disabled(inputText.isEmpty)
            }
            .padding()
            .background(Color(UIColor.systemGray6))
        }
        .navigationTitle("トーク")
        .onAppear { vm.startListening() }
        .onDisappear { vm.stopListening() }
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        let newMessage = Message(text: inputText, isMyMessage: true)
        vm.sendMessage(message: newMessage)   // Message 型で渡す
        inputText = ""
    }
}

/// 元の Message をそのまま使用
struct Message: Identifiable {
    let id = UUID()
    var text: String
    var isMyMessage: Bool
    var images: [UIImage] = []  // 既存
    var imageURLs: [String] = [] // 新規追加（Firestoreに保存する用）
}

/// 吹き出し
struct MessageRow: View {
    let message: Message
    
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


// MARK: - 日報保存側の例（Firestore対応）
class DailyReportManager {
    var storeName: String = "上杉"
    var date: Date = Date()
    var sales: String = "500000"
    var customerCount: String = "500"
    var wasteAmount: String = "10000"
    var notes: String = ""
    var images: [UIImage] = []

    // ChatView 側に渡すクロージャ（ローカル反映用）
    var sendToChat: ((Message) -> Void)?

    // Firestore
    private let db = Firestore.firestore()

    // 日報保存（Firestore & ローカルチャット）
    func saveReport() {
        let talkMessageText = """
        店名: \(storeName)
        日付: \(formattedDate(date))
        売上: \(sales)
        客数: \(customerCount)
        廃棄: \(wasteAmount)
        特記事項: \(notes)
        """

        // Message 型作成
        let message = Message(
            text: talkMessageText,
            isMyMessage: true,
            images: images
        )

        // Firestore に保存
        saveMessageToFirestore(message: message)

        // ローカルチャットにも送信
        sendToChat?(message)
    }

    // Firestore 保存用
    private func saveMessageToFirestore(message: Message) {
        var data: [String: Any] = [
            "text": message.text,
            "isMyMessage": message.isMyMessage,
            "timestamp": Date().timeIntervalSince1970
        ]

        // 画像URLがある場合は保存
        if !message.imageURLs.isEmpty {
            data["imageURLs"] = message.imageURLs
        }

        db.collection("dailyReports").addDocument(data: data) { error in
            if let error = error {
                print("Firestore 保存エラー: \(error)")
            }
        }
    }

    // 日付フォーマット
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

struct ChatViewWrapper: View {
    @Binding var messages: [Message]
    @State private var inputText: String = ""
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { message in
                            MessageRow(message: message)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            HStack {
                TextField("メッセージを入力", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                        .padding(8)
                }
                .disabled(inputText.isEmpty)
            }
            .padding()
            .background(Color(UIColor.systemGray6))
        }
        .navigationTitle("トーク")
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        messages.append(Message(text: inputText, isMyMessage: true))
        inputText = ""
    }

    func appendReport(_ reportText: String) {
        guard !reportText.isEmpty else { return }
        messages.append(Message(text: reportText, isMyMessage: true))
    }
}
