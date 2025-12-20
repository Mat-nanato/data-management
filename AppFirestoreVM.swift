import SwiftUI
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import FirebaseStorage

// ================================================
// MARK: - グローバル型定義（FirestoreShiftData / StaffShift）
// ================================================

struct FirestoreStaffShift: Codable {
    var id: String
    var staffName: String
    var ranges: [ShiftRange]  // 既存の ShiftRange 型を使用
}

struct FirestoreShiftData: Codable, Identifiable {
    @DocumentID var id: String? = nil
    var storeName: String
    var date: String          // "YYYY-MM-DD"
    var staffShifts: [FirestoreStaffShift]
}

// DailyShift 変換 extension
extension FirestoreShiftData {
    func mapToDailyShift() -> DailyShift {
        let staffShifts = self.staffShifts.map { s in
            StaffShift(
                id: UUID(uuidString: s.id) ?? UUID(),
                staffName: s.staffName,
                ranges: s.ranges
            )
        }
        return DailyShift(
            date: dateFormatter.date(from: date) ?? Date(),
            storeName: storeName,
            staffShifts: staffShifts
        )
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}

// ================================================
// MARK: - AppFirestoreVM
// ================================================

class AppFirestoreVM: ObservableObject {
    @Published var messages: [Message] = []
    private var db = Firestore.firestore()
    private var storage = Storage.storage()
    private var listener: ListenerRegistration?

    // -----------------------------
    // 画像付きメッセージ送信
    // -----------------------------
    func sendMessage(message: Message) {
        if message.images.isEmpty {
            saveMessageToFirestore(message: message)
        } else {
            var uploadedURLs: [String] = []
            let group = DispatchGroup()
            
            for image in message.images {
                group.enter()
                uploadImage(image) { url in
                    if let url = url { uploadedURLs.append(url) }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                var msg = message
                msg.imageURLs = uploadedURLs
                self.saveMessageToFirestore(message: msg)
            }
        }
    }

    func uploadImage(_ image: UIImage, completion: @escaping (String?) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(nil)
            return
        }
        let ref = storage.reference().child("chat_images/\(UUID().uuidString).jpg")
        ref.putData(imageData, metadata: nil) { _, error in
            if let error = error {
                print("画像アップロードエラー: \(error)")
                completion(nil)
                return
            }
            ref.downloadURL { url, _ in
                completion(url?.absoluteString)
            }
        }
    }

    private func saveMessageToFirestore(message: Message) {
        var data: [String: Any] = [
            "text": message.text,
            "isMyMessage": message.isMyMessage,
            "timestamp": Date().timeIntervalSince1970
        ]
        if !message.imageURLs.isEmpty {
            data["imageURLs"] = message.imageURLs
        }
        db.collection("dailyReports").addDocument(data: data) { error in
            if let error = error {
                print("Firestore送信エラー: \(error)")
            }
        }
    }

    // -----------------------------
    // 日報送信
    // -----------------------------
    func sendDailyReport(report: DailyReportData) {
        let data: [String: Any] = [
            "storeName": report.storeName,
            "date": report.date,
            "sales": report.sales,
            "customerCount": report.customerCount,
            "wasteAmount": report.wasteAmount,
            "orderAmount": report.orderAmount,
            "notes": report.notes,
            "imageURLs": report.imageURLs
        ]
        db.collection("dailyReports").addDocument(data: data) { error in
            if let error = error {
                print("Firestore日報送信エラー: \(error)")
            }
        }
    }

    // -----------------------------
    // 日報購読
    // -----------------------------
    func startListening() {
        listener = db.collection("dailyReports")
            .order(by: "timestamp")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self = self, let documents = snapshot?.documents else { return }
                self.messages = documents.map { doc in
                    let data = doc.data()
                    return Message(
                        text: data["text"] as? String ?? "",
                        isMyMessage: data["isMyMessage"] as? Bool ?? true,
                        images: [],
                        imageURLs: data["imageURLs"] as? [String] ?? []
                    )
                }
            }
    }

    func stopListening() {
        listener?.remove()
    }

    // -----------------------------
    // Firestore シフト購読
    // -----------------------------
    func startListeningShifts(completion: @escaping ([DailyShift]) -> Void) {
        db.collection("shifts")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }

                let shifts: [DailyShift] = documents.compactMap { doc in
                    do {
                        let fsShift = try doc.data(as: FirestoreShiftData.self)
                        return fsShift.mapToDailyShift()
                    } catch {
                        print("FirestoreShiftData 変換エラー: \(error)")
                        return nil
                    }
                }
                completion(shifts)
            }
    }
}
extension AppFirestoreVM {

    /// 先月集計情報を取得
    func fetchLastMonthSummary(storeName: String, completion: @escaping (_ sales: Int?, _ customerCount: Int?, _ avgUnit: Int?) -> Void) {
        let calendar = Calendar.current
        let now = Date()

        // 先月1日
        guard let startOfLastMonth = calendar.date(
            byAdding: .month,
            value: -1,
            to: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        ) else {
            completion(nil, nil, nil)
            return
        }

        // 先月末日
        guard let range = calendar.range(of: .day, in: .month, for: startOfLastMonth),
              let endOfLastMonth = calendar.date(
                byAdding: .day,
                value: range.count - 1,
                to: startOfLastMonth
              ) else {
            completion(nil, nil, nil)
            return
        }

        db.collection("dailyReports")
            .whereField("storeName", isEqualTo: storeName)
            .whereField("date", isGreaterThanOrEqualTo: formattedDate(startOfLastMonth))
            .whereField("date", isLessThanOrEqualTo: formattedDate(endOfLastMonth))
            .getDocuments { snapshot, error in
                if let error = error {
                    print("先月集計取得エラー: \(error)")
                    completion(nil, nil, nil)
                    return
                }

                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    completion(nil, nil, nil)
                    return
                }

                var totalSales = 0
                var totalCustomers = 0

                for doc in documents {
                    let data = doc.data()
                    let salesStr = data["sales"] as? String ?? "0"
                    let customersStr = data["customerCount"] as? String ?? "0"

                    let sales = Int(salesStr.replacingOccurrences(of: ",", with: "")) ?? 0
                    let customers = Int(customersStr.replacingOccurrences(of: ",", with: "")) ?? 0

                    totalSales += sales
                    totalCustomers += customers
                }

                let avgUnit = totalCustomers > 0 ? totalSales / totalCustomers : 0

                completion(totalSales, totalCustomers, avgUnit)
            }
    }
}


    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }



extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension AppFirestoreVM {
    func sendShiftToFirestore(dailyShift: DailyShift) {
        // DailyShift → FirestoreShiftData に変換
        let staffShifts = dailyShift.staffShifts.map { staff in
            FirestoreStaffShift(
                id: staff.id.uuidString,
                staffName: staff.staffName,
                ranges: staff.ranges
            )
        }
        
        let fsShift = FirestoreShiftData(
            id: nil,
            storeName: dailyShift.storeName,
            date: DateFormatter.yyyyMMdd.string(from: dailyShift.date),
            staffShifts: staffShifts
        )
        do {
            try db.collection("shifts")
                .document(fsShift.id ?? UUID().uuidString)
                .setData(from: fsShift) { error in
                    if let error = error {
                        print("Firestore シフト送信エラー: \(error)")
                    }
                }
        } catch {
            print("Firestore エンコードエラー: \(error)")
        }

    }
}

