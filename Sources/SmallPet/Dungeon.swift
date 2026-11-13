// Dungeon.swift —— 地下城的資料與規則。
//
// 她出門 minutes 分鐘，回來時依「戰鬥力 ÷ 建議戰鬥力」決定成功率。
// 成功就從 loot 抽一樣：服裝或零食。抽到已經有的服裝（或還沒畫好的服裝）就改給零食。
import Foundation

struct Dungeon: Identifiable {
    let id: String
    let name: String
    let recommendedPower: Int
    let minutes: Double
    let loot: [String]          // 服裝 id，或 Dungeon.snack
    let bossName: String        // 冒險時她在桌面上砍的 boss（圖在 Resources/props/boss_<id>_*.png）

    static let snack = "snack"

    static let all: [Dungeon] = [
        Dungeon(id: "meadow", name: "草原", recommendedPower: 15, minutes: 10,
                loot: ["straw_hat", "balloon", "bell_collar", "lollipop", snack], bossName: "草原史萊姆王"),
        Dungeon(id: "forest", name: "森林", recommendedPower: 40, minutes: 30,
                loot: ["witch_hat", "cape", "goggles", "backpack", "umbrella", snack], bossName: "古樹樹精"),
        Dungeon(id: "castle", name: "城堡", recommendedPower: 80, minutes: 60,
                loot: ["crown", "ribbon", "wings", "sword", snack], bossName: "黑暗騎士"),
        // 最高難度：成功也只有 1/4 機會掉 VIP 翅膀，其他是零食。
        Dungeon(id: "temple", name: "星空神殿", recommendedPower: 150, minutes: 120,
                loot: ["vip_wings", snack, snack, snack], bossName: "星空神龍"),
    ]

    static func find(_ id: String) -> Dungeon? { all.first { $0.id == id } }

    // 每天最多出門幾次。
    static let runsPerDay = 3

    // 測試用：環境變數 SMALLPET_FAST=1 時，分鐘變秒，不用真的等。
    static let timeScale: Double = ProcessInfo.processInfo.environment["SMALLPET_FAST"] == "1" ? 1 : 60

    var duration: TimeInterval { minutes * Self.timeScale }

    // 成功率：戰力等於建議值 70%，兩倍以上 95%，一半 20%，中間線性內插，最低 5%。
    func successChance(power: Int) -> Double {
        let r = Double(power) / Double(recommendedPower)
        switch r {
        case ..<0.5: return max(0.05, 0.2 * r / 0.5)
        case ..<1: return 0.2 + (r - 0.5) / 0.5 * 0.5
        case ..<2: return 0.7 + (r - 1) * 0.25
        default: return 0.95
        }
    }
}
