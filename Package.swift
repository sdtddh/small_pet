// swift-tools-version: 6.0
// Package.swift 是 Swift Package Manager 的設定檔，描述這個專案怎麼編譯。
import PackageDescription

let package = Package(
    name: "SmallPet",
    // 這是一個 macOS App，最低支援 macOS 13。
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // executableTarget = 可執行程式（有 main 進入點），用 `swift run` 就能跑。
        .executableTarget(
            name: "SmallPet",
            path: "Sources/SmallPet",
            // 寵物的圖片與 manifest.json 整個資料夾原封不動複製進 App，
            // 程式裡用 Bundle.module 取得。
            resources: [.copy("Resources")]
        )
    ]
)
