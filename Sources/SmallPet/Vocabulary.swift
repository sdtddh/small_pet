// Vocabulary.swift —— 背單字系統：詞書載入、Anki 式四階間隔重複（SM-2）、CSV/TSV 匯入匯出、離線發音與當日未學習提醒。
//
// 設計原則：
//   - 單字與複習進度跨角色共用，存在 ~/Library/Application Support/SmallPet/vocab.json（換角色不會重來）。
//   - 採用 Anki 主動回想流程：先看單字想意思 → 翻開答案 → 自選「重來 / 困難 / 良好 / 簡單」。
//   - 平常不主動彈出卡片打擾工作；只有在開啟「當日未學習提醒」、到了設定時間今天仍為 0 字且人在電腦前時，才溫和提醒一次。
import AppKit
import AVFoundation

// MARK: - 單字與詞書模型

struct VocabWord: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var word: String
    var phonetic: String
    var pos: String
    var meaning: String
    var example: String
    var deckID: String
    var lang: String

    init(id: String? = nil, word: String, phonetic: String = "", pos: String = "",
         meaning: String, example: String = "", deckID: String = VocabDeck.customID, lang: String = "en-US") {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id ?? "\(deckID):\(trimmed.lowercased())"
        self.word = trimmed
        self.phonetic = phonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pos = pos.trimmingCharacters(in: .whitespacesAndNewlines)
        self.meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        self.example = example.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deckID = deckID
        self.lang = lang
    }
}

struct VocabDeck: Identifiable, Equatable {
    static let customID = "custom"

    let id: String
    var name: String
    var description: String
    var lang: String
    var words: [VocabWord]
    var isCustom: Bool { id == Self.customID }
}

// builtin_decks.json 的解碼格式
private struct BuiltinDeckFile: Decodable {
    struct Entry: Decodable {
        let word: String
        let phonetic: String?
        let pos: String?
        let meaning: String
        let example: String?
    }
    let id: String
    let name: String
    let description: String
    let lang: String?
    let words: [Entry]
}

// MARK: - Anki 四階熟練度與 SM-2 排程

enum VocabRating: String, Codable, CaseIterable, Identifiable {
    case again   // 重來（沒記起來，本輪稍後再考）
    case hard    // 困難（想了很久才想起來）
    case good    // 良好（正常想起來）
    case easy    // 簡單（秒答、非常熟練）

    var id: String { rawValue }

    var title: String {
        switch self {
        case .again: "重來"
        case .hard:  "困難"
        case .good:  "良好"
        case .easy:  "簡單"
        }
    }

    var keyNumber: Int {
        switch self {
        case .again: 1
        case .hard:  2
        case .good:  3
        case .easy:  4
        }
    }
}

struct VocabProgress: Codable, Equatable {
    enum Stage { case learning, young, mature }

    var repetitions: Int = 0
    var intervalDays: Int = 0
    var easeFactor: Double = 2.5
    var dueAt: Date = .distantPast
    var lastRating: VocabRating?
    var lapses: Int = 0

    var stage: Stage {
        if repetitions == 0 { return .learning }
        return intervalDays >= 7 ? .mature : .young
    }
}

enum VocabScheduler {
    // 計算點下某個熟練度後的最新進度與按鈕上顯示的間隔文字（保證預覽與實際排程 100% 一致）。
    static func schedule(_ current: VocabProgress?, rating: VocabRating, now: Date = Date(),
                         calendar: Calendar = .current) -> (next: VocabProgress, label: String) {
        var p = current ?? VocabProgress(dueAt: now)
        p.lastRating = rating

        switch rating {
        case .again:
            if current != nil { p.lapses += 1 }
            p.repetitions = 0
            p.intervalDays = 0
            p.easeFactor = max(1.3, p.easeFactor - 0.20)
            p.dueAt = now.addingTimeInterval(10 * 60)
            return (p, "< 10分")

        case .hard:
            let days: Int
            if p.repetitions == 0 {
                p.repetitions = 1
                days = 1
            } else {
                days = min(365, max(p.intervalDays + 1, Int((Double(p.intervalDays) * 1.2).rounded())))
            }
            p.intervalDays = days
            p.easeFactor = max(1.3, p.easeFactor - 0.15)
            p.dueAt = nextDayStart(days: days, from: now, calendar: calendar)
            return (p, formatDays(days))

        case .good:
            let days: Int
            if current == nil {
                // 全新單字第一次就記得：3 天後複習
                p.repetitions = 1
                days = 3
            } else if p.repetitions == 0 {
                // 剛重來過的學習中單字：先隔 1～2 天穩固
                p.repetitions = 1
                days = 2
            } else {
                p.repetitions += 1
                days = min(365, max(p.intervalDays + 2, Int((Double(p.intervalDays) * p.easeFactor).rounded())))
            }
            p.intervalDays = days
            p.dueAt = nextDayStart(days: days, from: now, calendar: calendar)
            return (p, formatDays(days))

        case .easy:
            let days: Int
            if current == nil {
                p.repetitions = 1
                days = 7
            } else if p.repetitions == 0 {
                p.repetitions = 1
                days = 4
            } else {
                p.repetitions += 1
                days = min(365, max(p.intervalDays + 4, Int((Double(p.intervalDays) * p.easeFactor * 1.3).rounded())))
            }
            p.intervalDays = days
            p.easeFactor = min(3.2, p.easeFactor + 0.15)
            p.dueAt = nextDayStart(days: days, from: now, calendar: calendar)
            return (p, formatDays(days))
        }
    }

    // 跟 Anki 一樣以「隔天凌晨」為基準算天數，不會因為前一天晚上 11 點背，隔天白天還不能複習。
    private static func nextDayStart(days: Int, from now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: max(1, days), to: start) ?? now.addingTimeInterval(Double(days) * 86_400)
    }

    static func formatDays(_ days: Int) -> String {
        if days <= 0 { return "今天" }
        if days >= 60 {
            let months = Double(days) / 30.0
            return String(format: "%.1f 月", months).replacingOccurrences(of: ".0 ", with: " ")
        }
        return "\(days) 天"
    }
}

// MARK: - 存檔格式（vocab.json）

struct VocabSaveState: Codable {
    var enabledDeckIDs: [String] = ["core_english", "software_eng"]
    var customWords: [VocabWord] = []
    var progress: [String: VocabProgress] = [:]
    var dailyGoal: Int = 10
    var studiedDay: String = ""
    var studiedWordIDsToday: [String] = []
    var streak: Int = 0
    var lastStreakDay: String = ""
    var reminderEnabled: Bool = true
    var reminderHour: Int = 20
    var reminderMinute: Int = 0
    var lastRemindedDay: String = ""
    var autoSpeak: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VocabSaveState()
        enabledDeckIDs = try c.decodeIfPresent([String].self, forKey: .enabledDeckIDs) ?? d.enabledDeckIDs
        customWords = try c.decodeIfPresent([VocabWord].self, forKey: .customWords) ?? d.customWords
        progress = try c.decodeIfPresent([String: VocabProgress].self, forKey: .progress) ?? d.progress
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? d.dailyGoal
        studiedDay = try c.decodeIfPresent(String.self, forKey: .studiedDay) ?? d.studiedDay
        studiedWordIDsToday = try c.decodeIfPresent([String].self, forKey: .studiedWordIDsToday) ?? d.studiedWordIDsToday
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? d.streak
        lastStreakDay = try c.decodeIfPresent(String.self, forKey: .lastStreakDay) ?? d.lastStreakDay
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? d.reminderEnabled
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? d.reminderHour
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? d.reminderMinute
        lastRemindedDay = try c.decodeIfPresent(String.self, forKey: .lastRemindedDay) ?? d.lastRemindedDay
        autoSpeak = try c.decodeIfPresent(Bool.self, forKey: .autoSpeak) ?? d.autoSpeak
    }
}

// MARK: - 離線發音器

@MainActor
final class VocabSpeaker {
    static let shared = VocabSpeaker()
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String, lang: String = "en-US") {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: clean)
        let detected = Self.containsJapanese(clean) ? "ja-JP" : lang
        utterance.voice = AVSpeechSynthesisVoice(language: detected) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        utterance.volume = 0.85
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private static func containsJapanese(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)   // 平假名 / 片假名
        }
    }
}

// MARK: - 背單字核心控制器

@MainActor
final class VocabCenter: ObservableObject {

    enum StudyEvent {
        case again
        case remembered(rating: VocabRating, intervalText: String, reachedDailyGoal: Bool)
        case goalReached   // 沒有評分、但把每日目標調低到已學字數以下，因此剛好達標
    }

    @Published private(set) var state: VocabSaveState
    @Published private(set) var builtinDecks: [VocabDeck] = []
    @Published private(set) var currentWord: VocabWord?
    @Published var revealed = false

    // 交給 AppDelegate 串接：評分後的寵物反應與每日 XP 獎勵、當日未學習提醒。
    var onStudyEvent: ((StudyEvent) -> Void)?
    var onUnstudiedReminder: (() -> Void)?
    var canRemind: () -> Bool = { true }

    private let saveURL: URL
    private let calendar = Calendar.current
    private var queue: [String] = []            // 目前學習佇列中的單字 ID
    private var bonusNewAllowance = 0           // 今日達標後使用者點「再背 10 個」多開的新詞額度
    private var reminderTimer: Timer?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmallPet", isDirectory: true)
        saveURL = dir.appendingPathComponent("vocab.json")
        if let data = try? Data(contentsOf: saveURL),
           let saved = try? Self.decoder.decode(VocabSaveState.self, from: data) {
            state = saved
        } else {
            state = VocabSaveState()
        }
        builtinDecks = Self.loadBuiltinDecks()
        refreshDayIfNeeded()
        rebuildQueue()
        startReminderTimer()
    }

    // MARK: - 詞書與單字查詢

    var allDecks: [VocabDeck] {
        let custom = VocabDeck(
            id: VocabDeck.customID,
            name: "自訂與匯入單字",
            description: "你自己新增或從 CSV / Anki 匯入的單字",
            lang: "en-US",
            words: state.customWords
        )
        return state.customWords.isEmpty ? builtinDecks : builtinDecks + [custom]
    }

    private var wordMap: [String: VocabWord] {
        var map: [String: VocabWord] = [:]
        for deck in builtinDecks {
            for w in deck.words { map[w.id] = w }
        }
        for w in state.customWords { map[w.id] = w }
        return map
    }

    var enabledWords: [VocabWord] {
        let enabled = Set(state.enabledDeckIDs)
        var list: [VocabWord] = []
        for deck in builtinDecks where enabled.contains(deck.id) {
            list.append(contentsOf: deck.words)
        }
        if enabled.contains(VocabDeck.customID) {
            list.append(contentsOf: state.customWords)
        }
        return list
    }

    func isDeckEnabled(_ deckID: String) -> Bool {
        state.enabledDeckIDs.contains(deckID)
    }

    func setDeck(_ deckID: String, enabled: Bool) {
        if enabled {
            if !state.enabledDeckIDs.contains(deckID) { state.enabledDeckIDs.append(deckID) }
        } else {
            state.enabledDeckIDs.removeAll { $0 == deckID }
        }
        save()
        rebuildQueue()
    }

    func learnedCount(in deck: VocabDeck) -> Int {
        deck.words.filter { word in
            guard let p = state.progress[word.id] else { return false }
            return p.repetitions > 0
        }.count
    }

    func progress(for word: VocabWord) -> VocabProgress? {
        state.progress[word.id]
    }

    // 狀態摘要：新詞 / 學習中 / 待複習
    var counts: (new: Int, learning: Int, due: Int) {
        let end = endOfToday()
        var newCount = 0, learningCount = 0, dueCount = 0
        for w in enabledWords {
            guard let p = state.progress[w.id] else {
                newCount += 1
                continue
            }
            if p.repetitions == 0 {
                learningCount += 1
            } else if p.dueAt <= end {
                dueCount += 1
            }
        }
        return (newCount, learningCount, dueCount)
    }

    var studiedToday: Int {
        state.studiedDay == Self.todayString() ? state.studiedWordIDsToday.count : 0
    }

    var dailyGoal: Int { state.dailyGoal }
    var streak: Int { state.streak }
    var goalReachedToday: Bool { studiedToday >= state.dailyGoal }

    // MARK: - 翻卡與評分流程

    func reveal() {
        guard currentWord != nil, !revealed else { return }
        revealed = true
    }

    func speakCurrent() {
        guard let word = currentWord else { return }
        VocabSpeaker.shared.speak(word.word, lang: word.lang)
    }

    func previewInterval(for rating: VocabRating) -> String {
        guard let word = currentWord else { return "" }
        return VocabScheduler.schedule(state.progress[word.id], rating: rating).label
    }

    func grade(_ rating: VocabRating) {
        refreshDayIfNeeded()
        guard let word = currentWord else { return }
        let wasReached = goalReachedToday
        let scheduled = VocabScheduler.schedule(state.progress[word.id], rating: rating)
        state.progress[word.id] = scheduled.next

        // 先把這張從隊首移掉
        if queue.first == word.id {
            queue.removeFirst()
        } else {
            queue.removeAll { $0 == word.id }
        }

        if rating == .again {
            // 重來：排回本輪幾張之後再複習一次（Anki 同款行為）
            let insertAt = min(3, queue.count)
            queue.insert(word.id, at: insertAt)
            save()
            advanceToNextCard()
            onStudyEvent?(.again)
            return
        }

        // 困難 / 良好 / 簡單：計入今日已學單字（同一單字當天不重複灌水）
        let today = Self.todayString()
        if state.studiedDay != today {
            state.studiedDay = today
            state.studiedWordIDsToday = []
        }
        if !state.studiedWordIDsToday.contains(word.id) {
            state.studiedWordIDsToday.append(word.id)
        }
        updateStreak(today: today)
        save()

        let justReachedGoal = !wasReached && goalReachedToday
        advanceToNextCard()
        onStudyEvent?(.remembered(rating: rating, intervalText: scheduled.label, reachedDailyGoal: justReachedGoal))
    }

    // 今日佇列背完後，想再多背一點新單字時呼叫。
    func loadMoreNewWords(count: Int = 10) {
        bonusNewAllowance += max(1, count)
        rebuildQueue()
    }

    func rebuildQueue() {
        refreshDayIfNeeded()
        let end = endOfToday()
        let words = enabledWords
        var learningIDs: [String] = []
        var dueIDs: [String] = []
        var newIDs: [String] = []

        for w in words {
            if let p = state.progress[w.id] {
                if p.repetitions == 0 {
                    learningIDs.append(w.id)
                } else if p.dueAt <= end {
                    dueIDs.append(w.id)
                }
            } else {
                newIDs.append(w.id)
            }
        }
        dueIDs.sort { (state.progress[$0]?.dueAt ?? .distantPast) < (state.progress[$1]?.dueAt ?? .distantPast) }

        let remainingForGoal = max(0, state.dailyGoal - studiedToday)
        let newQuota = remainingForGoal + bonusNewAllowance
        let pickedNew = Array(newIDs.prefix(newQuota))

        queue = learningIDs + dueIDs + pickedNew
        let map = wordMap
        let next = queue.first.flatMap { map[$0] }
        let changed = next?.id != currentWord?.id
        currentWord = next
        if changed {
            revealed = false
            if state.autoSpeak, let next { VocabSpeaker.shared.speak(next.word, lang: next.lang) }
        }
    }

    private func advanceToNextCard() {
        if queue.isEmpty {
            rebuildQueue()
            return
        }
        let map = wordMap
        currentWord = queue.first.flatMap { map[$0] }
        revealed = false
        if state.autoSpeak, let word = currentWord {
            VocabSpeaker.shared.speak(word.word, lang: word.lang)
        }
    }

    // MARK: - 設定更新

    func setDailyGoal(_ goal: Int) {
        refreshDayIfNeeded()
        let wasReached = goalReachedToday
        state.dailyGoal = min(max(goal, 5), 100)
        save()
        rebuildQueue()
        // 今天已學 8 字、把目標從 10 調成 5：當下就算達標（獎勵每天只領一次，由 PetStats 把關）。
        if !wasReached, goalReachedToday, studiedToday > 0 { onStudyEvent?(.goalReached) }
    }

    func setAutoSpeak(_ on: Bool) {
        state.autoSpeak = on
        save()
    }

    func setReminder(enabled: Bool, hour: Int? = nil, minute: Int? = nil) {
        state.reminderEnabled = enabled
        if let hour { state.reminderHour = min(max(hour, 0), 23) }
        if let minute { state.reminderMinute = min(max(minute, 0), 59) }
        save()
    }

    // MARK: - 自訂新增、刪除與 CSV / TSV（Anki）匯入匯出

    @discardableResult
    func addCustomWord(word: String, phonetic: String = "", pos: String = "", meaning: String, example: String = "") -> Bool {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !m.isEmpty else { return false }
        let entry = VocabWord(word: w, phonetic: phonetic, pos: pos, meaning: m, example: example, deckID: VocabDeck.customID)
        if let idx = state.customWords.firstIndex(where: { $0.id == entry.id }) {
            state.customWords[idx] = entry
        } else {
            state.customWords.insert(entry, at: 0)
        }
        if !state.enabledDeckIDs.contains(VocabDeck.customID) {
            state.enabledDeckIDs.append(VocabDeck.customID)
        }
        save()
        rebuildQueue()
        return true
    }

    func deleteCustomWord(_ id: String) {
        state.customWords.removeAll { $0.id == id }
        state.progress.removeValue(forKey: id)
        save()
        rebuildQueue()
    }

    func resetProgress(for wordID: String) {
        state.progress.removeValue(forKey: wordID)
        save()
        rebuildQueue()
    }

    // 匯入 CSV / TSV / Anki 純文字檔：回傳成功匯入或更新的筆數。
    // 支援格式：
    //   - 2 欄：單字, 解釋
    //   - 3 欄：單字, 解釋, 例句
    //   - 4 欄：單字, 音標, 解釋, 例句
    //   - 5 欄（完整匯出格式）：單字, 音標, 詞性, 解釋, 例句
    //   - 自動忽略 `#` 開頭的 Anki 檔頭註解與簡單的 HTML 標籤（如 <br>）。
    func importText(_ content: String) -> Int {
        var added = 0
        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            // 只去掉空格與換行，保留 tab：行尾的空白欄位（例如沒有例句）也要算一欄，欄位才對得上。
            let trimmed = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " \r\n"))
            if trimmed.trimmingCharacters(in: .whitespaces).isEmpty || trimmed.hasPrefix("#") { continue }
            let cols = Self.parseDelimitedLine(trimmed).map(Self.stripSimpleHTML)
            guard cols.count >= 2 else { continue }
            // 略過常見標題列
            let firstLower = cols[0].lowercased()
            if (firstLower == "word" || firstLower == "單字" || firstLower == "front") &&
               (cols[1].lowercased() == "meaning" || cols[1] == "解釋" || cols[1].lowercased() == "back") {
                continue
            }
            let entry: VocabWord
            if cols.count >= 5 {
                entry = VocabWord(word: cols[0], phonetic: cols[1], pos: cols[2], meaning: cols[3], example: cols[4])
            } else if cols.count == 4 {
                entry = VocabWord(word: cols[0], phonetic: cols[1], meaning: cols[2], example: cols[3])
            } else if cols.count == 3 {
                entry = VocabWord(word: cols[0], meaning: cols[1], example: cols[2])
            } else {
                entry = VocabWord(word: cols[0], meaning: cols[1])
            }
            guard !entry.word.isEmpty, !entry.meaning.isEmpty else { continue }
            if let idx = state.customWords.firstIndex(where: { $0.id == entry.id }) {
                state.customWords[idx] = entry
            } else {
                state.customWords.append(entry)
            }
            added += 1
        }
        if added > 0 {
            if !state.enabledDeckIDs.contains(VocabDeck.customID) {
                state.enabledDeckIDs.append(VocabDeck.customID)
            }
            save()
            rebuildQueue()
        }
        return added
    }

    // 匯出為與 Anki 相容的 UTF-8 TSV 格式。
    func exportTSV(onlyCustom: Bool = false) -> String {
        let source = onlyCustom ? state.customWords : enabledWords
        var rows = ["#separator:tab", "#columns:word\tphonetic\tpos\tmeaning\texample"]
        for w in source {
            let fields = [w.word, w.phonetic, w.pos, w.meaning, w.example]
                .map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
            rows.append(fields.joined(separator: "\t"))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func parseDelimitedLine(_ line: String) -> [String] {
        if line.contains("\t") {
            return line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        var result: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            i += 1
            if ch == "\"" {
                // 引號欄位裡的 "" 代表一個雙引號（標準 CSV 跳脫寫法）
                if inQuotes, i < chars.count, chars[i] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    private static func stripSimpleHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: .regularExpression)
         .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 當日未學習提醒與跨日處理

    private func startReminderTimer() {
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkReminderTick() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        reminderTimer = timer
    }

    private func checkReminderTick() {
        let previousDay = state.studiedDay
        refreshDayIfNeeded()
        if previousDay != state.studiedDay { rebuildQueue() }

        guard state.reminderEnabled else { return }
        let today = Self.todayString()
        guard state.lastRemindedDay != today, studiedToday == 0 else { return }
        guard !enabledWords.isEmpty else { return }

        let now = Date()
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let targetMinutes = state.reminderHour * 60 + state.reminderMinute
        guard nowMinutes >= targetMinutes else { return }

        // 使用者離開電腦超過 5 分鐘，或寵物隱藏 / 專注中，就先不打擾，等回來再提醒。
        guard ReminderCenter.secondsSinceLastInput() < ReminderCenter.idleLimit, canRemind() else { return }

        state.lastRemindedDay = today
        save()
        onUnstudiedReminder?()
    }

    private func refreshDayIfNeeded() {
        let today = Self.todayString()
        if state.studiedDay != today {
            state.studiedDay = today
            state.studiedWordIDsToday = []
            bonusNewAllowance = 0
        }
        // 若昨天也沒背、今天也沒背，連續天數歸零
        if !state.lastStreakDay.isEmpty,
           state.lastStreakDay != today,
           state.lastStreakDay != Self.yesterdayString() {
            state.streak = 0
        }
    }

    private func updateStreak(today: String) {
        guard state.lastStreakDay != today else { return }
        if state.lastStreakDay == Self.yesterdayString() {
            state.streak += 1
        } else {
            state.streak = 1
        }
        state.lastStreakDay = today
    }

    private func endOfToday() -> Date {
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
    }

    // MARK: - 載入與儲存

    private static func loadBuiltinDecks() -> [VocabDeck] {
        guard let url = Bundle.module.url(forResource: "Resources", withExtension: nil)?
            .appendingPathComponent("shared/vocab/builtin_decks.json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([BuiltinDeckFile].self, from: data) else {
            return []
        }
        return raw.map { d in
            let lang = d.lang ?? "en-US"
            let words = d.words.map { e in
                VocabWord(word: e.word, phonetic: e.phonetic ?? "", pos: e.pos ?? "",
                          meaning: e.meaning, example: e.example ?? "", deckID: d.id, lang: lang)
            }
            return VocabDeck(id: d.id, name: d.name, description: d.description, lang: lang, words: words)
        }
    }

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
            NSLog("單字存檔失敗：\(error)")
        }
    }

    static func todayString(from date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func yesterdayString() -> String {
        let y = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return todayString(from: y)
    }
}
