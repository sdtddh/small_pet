// Character.swift —— 可以切換的角色。
//
// 每個角色有自己的資料夾 Resources/characters/<id>/（本體、服裝、manifest.json、phrases.json），
// 自己的存檔（等級、背包、地下城）和自己的衣櫃。家具（Resources/props）大家共用。
// 切換角色時 App 會自動重開，所有東西重新載入成新角色的。
import AppKit

enum Character {
    // 選單上的順序。id 要跟資料夾名稱一樣。
    static let all: [(id: String, name: String)] = [
        ("amiya", "阿米婭"),
        ("rim", "理芽"),
    ]

    private static let defaultsKey = "character"

    // 目前的角色（存在 UserDefaults，不認識的 id 就退回第一個）。
    static let current: String = {
        migrateRenamed()
        let saved = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return all.contains { $0.id == saved } ? saved : all[0].id
    }()

    // v1.2.0 的「カフ」(id kaf) 後來改名成「理芽」(id rim)：把選擇、存檔、衣櫃搬過去。
    private static func migrateRenamed() {
        let d = UserDefaults.standard
        let (old, new) = ("kaf", "rim")
        if d.string(forKey: defaultsKey) == old { d.set(new, forKey: defaultsKey) }
        if let outfits = d.dictionary(forKey: "equippedOutfits.\(old)") {
            if d.dictionary(forKey: "equippedOutfits.\(new)") == nil { d.set(outfits, forKey: "equippedOutfits.\(new)") }
            d.removeObject(forKey: "equippedOutfits.\(old)")
        }
        if let look = d.dictionary(forKey: "look.\(old)") {   // 外觀（髮型 / 衣服）
            if d.dictionary(forKey: "look.\(new)") == nil { d.set(look, forKey: "look.\(new)") }
            d.removeObject(forKey: "look.\(old)")
        }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmallPet", isDirectory: true)
        let from = dir.appendingPathComponent("save-\(old).json"), to = dir.appendingPathComponent("save-\(new).json")
        if FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) {
            try? FileManager.default.moveItem(at: from, to: to)
        }
    }

    // 阿米婭是原本就有的角色，沿用舊的存檔名稱，升級後進度不會不見。
    static var isOriginal: Bool { current == all[0].id }

    // 換角色：記下來，然後重開 App。
    @MainActor
    static func switchTo(_ id: String) {
        guard id != current else { return }
        UserDefaults.standard.set(id, forKey: defaultsKey)
        relaunch()
    }

    @MainActor
    private static func relaunch() {
        let bundle = Bundle.main.bundleURL
        let task = Process()
        if bundle.pathExtension == "app" {
            // 等這個行程結束再開新的（open -n 允許同一個 App 開第二份）。
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$0\"", bundle.path]
        } else {
            // swift run 的執行檔不是 .app，直接重新執行同一個檔案。
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "sleep 0.5; \"$0\" >/dev/null 2>&1 &", CommandLine.arguments[0]]
        }
        try? task.run()
        NSApp.terminate(nil)
    }
}
