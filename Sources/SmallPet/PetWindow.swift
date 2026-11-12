// PetWindow.swift —— 桌寵專用的視窗。
//
// 桌面寵物需要一個「透明、無邊框、永遠浮在最上層、可以到處放」的視窗。
// 這些都是靠設定 NSWindow 的屬性達成，是這個專案最「Mac 原生」的部分。
import AppKit

final class PetWindow: NSWindow {

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            // .borderless：沒有標題列、沒有紅綠燈按鈕。
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // 視窗背景透明，只看得到我們畫的寵物。
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // .floating：層級高於一般視窗，讓寵物永遠浮在最上面。
        level = .floating

        // 讓寵物在「所有桌面 / 全螢幕 App 之上」也看得到。
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 不需要出現在視窗選單、Mission Control 的一般視窗列。
        isExcludedFromWindowsMenu = true

        // 允許用滑鼠把整個視窗拖著跑（配合 PetView 的拖曳）。
        isMovableByWindowBackground = true
    }

    // 無邊框視窗預設不能成為 key/main window，覆寫成可以，
    // 這樣才能正常接收滑鼠事件。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
