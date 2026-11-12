// main.swift —— 程式進入點。
//
// 一般 macOS App 用 @main + SwiftUI/AppKit 的 App 協定啟動；
// 但用 Swift Package 的可執行檔時，最直接的方式是自己建立 NSApplication。
import AppKit

// 建立整個應用程式的單例（每個 App 只有一個 NSApplication）。
let app = NSApplication.shared

// .accessory：不會出現在 Dock、不搶焦點，很適合「常駐桌面的小工具」。
// 若想要 Dock 圖示，改成 .regular。
app.setActivationPolicy(.accessory)

// 建立我們的委任物件（負責視窗、動畫、選單的邏輯），
// 用一個變數 hold 住它，避免被記憶體回收。
let delegate = AppDelegate()
app.delegate = delegate

// 進入事件迴圈，程式開始跑（直到使用者選「結束」）。
app.run()
