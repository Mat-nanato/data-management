#!/usr/bin/swift
import Foundation

// URL から JSON を取得してログに出力する簡単なスクリプト
let url = URL(string: "http://localhost:3000/latest-info")!

let task = URLSession.shared.dataTask(with: url) { data, response, error in
    if let error = error {
        print("❌ エラー:", error)
        return
    }
    guard let data = data else {
        print("データが空")
        return
    }
    if let str = String(data: data, encoding: .utf8) {
        print("📄 LatestInfo JSON:", str)
    }
}

task.resume()
RunLoop.main.run() // 非同期処理が終了するまで待つ

