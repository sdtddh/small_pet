// PetStats.swift —— 練等與冒險的進度：等級、經驗值、餵食次數、背包、地下城，以及存檔。
//
// 規則：
//   - 每天可以餵 2 次，每次 +20 XP，次數在當地時間 0 點重置。吃零食也 +20 XP，但不佔每天的次數。
//   - 升到下一級需要「50 × 目前等級」XP，多出來的 XP 會留到下一級。
//   - 戰鬥力 = 等級 × 10 + 身上服裝的加成。
//   - 每天最多出門冒險 3 次（規則在 Dungeon.swift）。
// 存檔是 ~/Library/Application Support/SmallPet/save.json（其他角色是 save-<角色>.json），重開 App 還在。
import Foundation

struct GameState: Codable {
    struct Run: Codable {
        var dungeonID: String
        var endsAt: Date
        var power: Int            // 出發時的戰鬥力（回來時用這個算成功率）
    }
    struct LogEntry: Codable, Identifiable {
        var date: Date
        var text: String
        var id: Date { date }
    }

    var level = 1
    var xp = 0                // 這一級已經累積的 XP
    var feedDay = ""          // 最後一次餵食是哪一天（yyyy-MM-dd）
    var feedsUsed = 0         // 那一天已經餵了幾次
    var snacks = 0            // 背包裡的零食
    var unlocked: [String] = []   // 從地下城拿到的服裝
    var runDay = ""           // 最後一次出門是哪一天
    var runsUsed = 0          // 那一天已經出門幾次
    var run: Run?             // 正在冒險中（nil 代表在家）
    var log: [LogEntry] = []  // 戰報，新的在前面

    init() {}

    // 舊存檔沒有後來加的欄位，缺的就用預設值，不會整個讀不出來。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameState()
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? d.level
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? d.xp
        feedDay = try c.decodeIfPresent(String.self, forKey: .feedDay) ?? d.feedDay
        feedsUsed = try c.decodeIfPresent(Int.self, forKey: .feedsUsed) ?? d.feedsUsed
        snacks = try c.decodeIfPresent(Int.self, forKey: .snacks) ?? d.snacks
        unlocked = try c.decodeIfPresent([String].self, forKey: .unlocked) ?? d.unlocked
        runDay = try c.decodeIfPresent(String.self, forKey: .runDay) ?? d.runDay
        runsUsed = try c.decodeIfPresent(Int.self, forKey: .runsUsed) ?? d.runsUsed
        run = try c.decodeIfPresent(Run.self, forKey: .run)
        log = try c.decodeIfPresent([LogEntry].self, forKey: .log) ?? d.log
    }
}

@MainActor
final class PetStats: ObservableObject {

    // 可以調整的數值。
    static let feedsPerDay = 2
    static let xpPerFeed = 20
    static func xpToNext(level: Int) -> Int { 50 * level }
    static let maxLog = 20

    @Published private(set) var state: GameState
    // 身上服裝的戰鬥力加成，換裝時由外部更新。
    @Published var outfitBonus = 0

    private let saveURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmallPet", isDirectory: true)
        // 每個角色各自練等；第一個角色沿用舊檔名。
        saveURL = dir.appendingPathComponent(Character.isOriginal ? "save.json" : "save-\(Character.current).json")
        if let data = try? Data(contentsOf: saveURL),
           let saved = try? Self.decoder.decode(GameState.self, from: data) {
            state = saved
        } else {
            state = GameState()
        }
    }

    // MARK: - 查詢

    var level: Int { state.level }
    var xp: Int { state.xp }
    var xpNeeded: Int { Self.xpToNext(level: state.level) }
    var power: Int { state.level * 10 + outfitBonus }
    var snacks: Int { state.snacks }
    var run: GameState.Run? { state.run }

    // 今天還能餵幾次（跨日就自動恢復）。
    var feedsLeft: Int {
        let used = state.feedDay == Self.today() ? state.feedsUsed : 0
        return max(0, Self.feedsPerDay - used)
    }

    // 今天還能出門幾次。
    var runsLeft: Int {
        let used = state.runDay == Self.today() ? state.runsUsed : 0
        return max(0, Dungeon.runsPerDay - used)
    }

    func owns(_ outfitID: String) -> Bool { state.unlocked.contains(outfitID) }

    // MARK: - 餵食

    enum FeedResult {
        case none                               // 今天已經餵滿了 / 沒有零食
        case fed(xp: Int, newLevel: Int?)       // 拿到多少 XP；有升等的話是新的等級
    }

    func feed() -> FeedResult {
        guard feedsLeft > 0 else { return .none }
        let today = Self.today()
        if state.feedDay != today {
            state.feedDay = today
            state.feedsUsed = 0
        }
        state.feedsUsed += 1
        return gainFeedXP()
    }

    // 吃一包零食：跟餵食一樣拿 XP，但不佔今天的次數。
    func eatSnack() -> FeedResult {
        guard state.snacks > 0 else { return .none }
        state.snacks -= 1
        return gainFeedXP()
    }

    private func gainFeedXP() -> FeedResult {
        let before = state.level
        state.xp += Self.xpPerFeed
        while state.xp >= xpNeeded {
            state.xp -= xpNeeded
            state.level += 1
        }
        save()
        return .fed(xp: Self.xpPerFeed, newLevel: state.level > before ? state.level : nil)
    }

    // MARK: - 地下城

    enum StartError: Error {
        case busy          // 已經在冒險中
        case noRunsLeft    // 今天出門次數用完了
    }

    func startRun(_ dungeon: Dungeon) -> StartError? {
        guard state.run == nil else { return .busy }
        guard runsLeft > 0 else { return .noRunsLeft }
        let today = Self.today()
        if state.runDay != today {
            state.runDay = today
            state.runsUsed = 0
        }
        state.runsUsed += 1
        state.run = GameState.Run(dungeonID: dungeon.id, endsAt: Date().addingTimeInterval(dungeon.duration), power: power)
        save()
        return nil
    }

    // 冒險時間到了沒。
    var runFinished: Bool {
        guard let run = state.run else { return false }
        return Date() >= run.endsAt
    }

    enum Reward {
        case outfit(id: String, name: String)
        case snack
    }
    struct RunResult {
        let dungeon: Dungeon
        let reward: Reward?     // nil 代表失敗
    }

    // 結算冒險：擲骰決定成敗、發獎品、寫戰報。
    // - outfits：目前素材裡有的服裝（還沒畫好的服裝不會掉，改給零食）。
    func finishRun(outfits: [Manifest.Outfit]) -> RunResult? {
        guard let run = state.run else { return nil }
        state.run = nil
        guard let dungeon = Dungeon.find(run.dungeonID) else {
            save()
            return nil
        }

        var reward: Reward?
        if Double.random(in: 0..<1) < dungeon.successChance(power: run.power) {
            let pick = dungeon.loot.randomElement() ?? Dungeon.snack
            if let outfit = outfits.first(where: { $0.id == pick }), !owns(pick) {
                state.unlocked.append(pick)
                reward = .outfit(id: pick, name: outfit.name)
            } else {
                state.snacks += 1
                reward = .snack
            }
        }

        let text: String
        switch reward {
        case .outfit(_, let name)?: text = "\(dungeon.name)：成功！拿到「\(name)」"
        case .snack?: text = "\(dungeon.name)：成功！拿到零食 ×1"
        case nil: text = "\(dungeon.name)：失敗…（出發時戰鬥力 \(run.power)）"
        }
        state.log.insert(GameState.LogEntry(date: Date(), text: text), at: 0)
        if state.log.count > Self.maxLog { state.log.removeLast(state.log.count - Self.maxLog) }
        save()
        return RunResult(dungeon: dungeon, reward: reward)
    }

    // MARK: - 存檔

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func save() {
        do {
            try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: saveURL, options: .atomic)
        } catch {
            NSLog("存檔失敗：\(error)")
        }
    }

    private static func today() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
