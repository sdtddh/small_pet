// InputSync.swift —— 「跟著我打字 / 點擊」：偵測你在任何 App 裡按鍵盤、點滑鼠，讓她跟著做動作。
//
// 隱私：這裡只知道「按了一個鍵」「在哪裡點了一下」，完全不讀是哪個鍵、打了什麼字。
// 密碼欄位等安全輸入時，macOS 本來就不會把按鍵送給其他 App。
//
// 權限：
//   - 滑鼠點擊不需要額外權限。
//   - 鍵盤需要「系統設定 → 隱私權與安全性 → 輔助使用」允許 SmallPet。
//     打開這個功能時會跳出系統的詢問視窗；允許之後幾秒內就會開始生效，不用重開 App。
import AppKit

@MainActor
final class InputSync {

    private static let defaultsKey = "inputSync"

    // 按了一個鍵 / 在螢幕上的某個位置點了一下。
    var onKey: (() -> Void)?
    var onClick: ((NSPoint) -> Void)?

    private(set) var enabled: Bool
    private var monitors: [Any] = []
    private var keyboardMonitored = false
    private var permissionTimer: Timer?

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        if enabled { start(askPermission: false) }
    }

    // 鍵盤有沒有權限（輔助使用）。
    var keyboardAllowed: Bool { AXIsProcessTrusted() }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.defaultsKey)
        if on { start(askPermission: true) } else { stop() }
    }

    private func start(askPermission: Bool) {
        stop()
        // 全域監聽：只收得到送給「其他」App 的事件；點在她身上的事件走她自己的滑鼠處理，不會重複。
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated { [weak self] in self?.onClick?(NSEvent.mouseLocation) }
        }) {
            monitors.append(m)
        }

        if keyboardAllowed {
            addKeyboardMonitor()
        } else {
            if askPermission {
                // 跳出系統的「要允許輔助使用嗎」視窗
                AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            // 每 2 秒看一下權限給了沒，給了就開始聽鍵盤
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.enabled, self.keyboardAllowed else { return }
                    self.addKeyboardMonitor()
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            permissionTimer = timer
        }
    }

    private func addKeyboardMonitor() {
        guard !keyboardMonitored else { return }
        // 只看「有按鍵」：按住不放的自動重複不算，也不讀 event.characters
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            guard !event.isARepeat else { return }
            MainActor.assumeIsolated { [weak self] in self?.onKey?() }
        }) {
            monitors.append(m)
            keyboardMonitored = true
        }
    }

    private func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        keyboardMonitored = false
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // 打開「輔助使用」設定頁，讓你手動勾選 SmallPet。
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
