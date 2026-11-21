// Reminders.swift —— 生活與專注提醒：番茄鐘、倒數計時、喝水、鬧鐘、行事曆。
//
// 這裡只負責「什麼時候該提醒、提醒什麼」；提醒的樣子（她說話、做動作、旁邊跳出小卡片）
// 由 AppDelegate 收到 onReminder 之後處理。
//
// 溫和的原則：
//   - 不搶焦點、不跳系統通知；卡片出現在她旁邊，按「好」就收起來。
//   - 倒數、鬧鐘時間到會一直響鈴（鈴聲可以選、可以試聽），按卡片上任一個按鈕才停；其他提醒只輕輕響一聲。
//   - 喝水提醒：你離開電腦（5 分鐘沒動鍵盤滑鼠）時不提醒，回來後重新計時。
//   - 番茄鐘專注中她會安靜一點（不自己碎念）。
//
// 設定存在 UserDefaults；番茄鐘、倒數計時、鬧鐘關掉 App 再開也會接著算。
// 行事曆要「行事曆」權限，只讀今天接下來的行程時間和標題，不會修改或上傳任何東西。
import AppKit
import EventKit

// 一則提醒：卡片上的內容和按鈕。
struct Reminder {
    enum Kind { case focusDone, breakDone, countdown, water, alarm, calendar }

    struct Action {
        let title: String
        let run: () -> Void
    }

    let kind: Kind
    let icon: String          // emoji
    let title: String
    let message: String
    var actions: [Action] = []
    var autoDismiss: Double?  // 幾秒後自己收起來（nil：等你按）
}

@MainActor
final class ReminderCenter: ObservableObject {

    var onReminder: ((Reminder) -> Void)?
    var onTick: (() -> Void)?   // 每秒一次（更新選單列的倒數）

    // 番茄鐘、喝水、行事曆提醒時輕輕響一聲
    @Published var soundOn: Bool { didSet { defaults.set(soundOn, forKey: "reminderSound") } }
    // 倒數、鬧鐘的鈴聲（系統音效的名字；"" = 不響）
    @Published var countdownSound: String { didSet { defaults.set(countdownSound, forKey: "countdownSound") } }
    @Published var alarmSound: String { didSet { defaults.set(alarmSound, forKey: "alarmSound") } }

    // MARK: - 番茄鐘

    enum PomodoroPhase: String, Codable { case idle, focus, shortBreak, longBreak }

    struct PomodoroState: Codable {
        var phase: PomodoroPhase = .idle
        var endsAt: Date?
        var pausedLeft: Double?    // 暫停時剩下的秒數
        var round = 0              // 這一組完成了幾輪專注（每 4 輪一次長休息）
    }

    @Published private(set) var pomodoro = PomodoroState() { didSet { save(pomodoro, "pomodoro") } }
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var breakMinutes: Int { didSet { defaults.set(breakMinutes, forKey: "breakMinutes") } }
    @Published var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: "longBreakMinutes") } }
    @Published private(set) var focusDoneToday = 0

    var focusing: Bool { pomodoro.phase == .focus && pomodoro.pausedLeft == nil }

    func startFocus() {
        pomodoro.phase = .focus
        pomodoro.endsAt = Date().addingTimeInterval(Double(focusMinutes) * 60)
        pomodoro.pausedLeft = nil
    }

    func startBreak(long: Bool) {
        pomodoro.phase = long ? .longBreak : .shortBreak
        pomodoro.endsAt = Date().addingTimeInterval(Double(long ? longBreakMinutes : breakMinutes) * 60)
        pomodoro.pausedLeft = nil
    }

    func togglePausePomodoro() {
        guard pomodoro.phase != .idle else { return }
        if let left = pomodoro.pausedLeft {
            pomodoro.endsAt = Date().addingTimeInterval(left)
            pomodoro.pausedLeft = nil
        } else if let end = pomodoro.endsAt {
            pomodoro.pausedLeft = max(0, end.timeIntervalSinceNow)
        }
    }

    func stopPomodoro() {
        pomodoro = PomodoroState()
    }

    // 專注 / 休息還剩幾秒。
    func pomodoroLeft(now: Date = Date()) -> Double? {
        guard pomodoro.phase != .idle else { return nil }
        if let left = pomodoro.pausedLeft { return left }
        return pomodoro.endsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    private func checkPomodoro(now: Date) {
        guard pomodoro.phase != .idle, pomodoro.pausedLeft == nil, let end = pomodoro.endsAt, now >= end else { return }
        // 關掉 App 或電腦睡著，錯過太久（超過 10 分鐘）：這一輪就靜靜結束，不再補提醒
        if now.timeIntervalSince(end) > 10 * 60 {
            pomodoro = PomodoroState(phase: .idle, round: pomodoro.round)
            return
        }
        switch pomodoro.phase {
        case .focus:
            pomodoro.round += 1
            focusDoneToday += 1
            defaults.set(focusDoneToday, forKey: "focusDoneToday")
            let long = pomodoro.round % 4 == 0
            startBreak(long: long)
            let minutes = long ? longBreakMinutes : breakMinutes
            onReminder?(Reminder(
                kind: .focusDone, icon: "🍅", title: "專注完成！今天第 \(focusDoneToday) 個番茄",
                message: "站起來伸伸懶腰、看看遠方，休息 \(minutes) 分鐘吧。",
                actions: [
                    .init(title: "好") {},
                    .init(title: "跳過休息") { [weak self] in self?.startFocus() },
                ]))
        case .shortBreak, .longBreak:
            pomodoro = PomodoroState(phase: .idle, round: pomodoro.round % 4)
            onReminder?(Reminder(
                kind: .breakDone, icon: "☕️", title: "休息時間結束",
                message: "準備好就開始下一輪專注吧，不急。",
                actions: [
                    .init(title: "開始專注") { [weak self] in self?.startFocus() },
                    .init(title: "先不要") {},
                ]))
        case .idle:
            break
        }
    }

    // MARK: - 倒數計時

    struct CountdownState: Codable {
        var label: String
        var total: Double
        var endsAt: Date?
        var pausedLeft: Double?
    }

    @Published private(set) var countdown: CountdownState? { didSet { save(countdown, "countdown") } }

    func startCountdown(seconds: Double, label: String) {
        let seconds = max(1, seconds)
        countdown = CountdownState(label: label, total: seconds, endsAt: Date().addingTimeInterval(seconds))
    }

    func togglePauseCountdown() {
        guard var c = countdown else { return }
        if let left = c.pausedLeft {
            c.endsAt = Date().addingTimeInterval(left)
            c.pausedLeft = nil
        } else if let end = c.endsAt {
            c.pausedLeft = max(0, end.timeIntervalSinceNow)
        }
        countdown = c
    }

    func cancelCountdown() { countdown = nil }

    func countdownLeft(now: Date = Date()) -> Double? {
        guard let c = countdown else { return nil }
        if let left = c.pausedLeft { return left }
        return c.endsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    private func checkCountdown(now: Date) {
        guard let c = countdown, c.pausedLeft == nil, let end = c.endsAt, now >= end else { return }
        countdown = nil
        let label = c.label.trimmingCharacters(in: .whitespaces)
        onReminder?(Reminder(
            kind: .countdown, icon: "⏰", title: label.isEmpty ? "時間到了" : "時間到：\(label)",
            message: "\(Self.durationText(c.total))的倒數結束了。",
            actions: [
                .init(title: "好") {},
                .init(title: "再 5 分鐘") { [weak self] in self?.startCountdown(seconds: 5 * 60, label: label) },
            ]))
    }

    // MARK: - 喝水

    @Published var waterEnabled: Bool { didSet { defaults.set(waterEnabled, forKey: "waterEnabled"); resetWater() } }
    @Published var waterInterval: Int { didSet { defaults.set(waterInterval, forKey: "waterInterval"); resetWater() } }
    @Published private(set) var cupsToday = 0
    @Published private(set) var nextWaterAt: Date?
    static let idleLimit: Double = 5 * 60    // 離開電腦這麼久就當作不在

    func drankWater() {
        cupsToday += 1
        defaults.set(cupsToday, forKey: "cupsToday")
        resetWater()
    }

    private func resetWater(from now: Date = Date()) {
        nextWaterAt = waterEnabled ? now.addingTimeInterval(Double(waterInterval) * 60) : nil
    }

    private func checkWater(now: Date, idle: Double) {
        guard waterEnabled, let next = nextWaterAt else { return }
        // 你不在電腦前：不提醒，回來後重新算一個完整的間隔
        if idle >= Self.idleLimit {
            resetWater(from: now)
            return
        }
        guard now >= next else { return }
        resetWater(from: now)
        let lines = ["喝口水吧，身體會感謝你的。", "補充一點水分，眼睛也順便休息一下。", "一起喝杯水，順便伸個懶腰～"]
        onReminder?(Reminder(
            kind: .water, icon: "💧", title: "該喝水了",
            message: lines.randomElement()!,
            actions: [
                .init(title: "喝了！") { [weak self] in self?.drankWater() },
                .init(title: "等等") { [weak self] in self?.snoozeWater() },
            ],
            autoDismiss: 120))
    }

    private func snoozeWater() {
        nextWaterAt = Date().addingTimeInterval(10 * 60)
    }

    // MARK: - 鬧鐘（自己設的時間）

    struct Alarm: Codable, Identifiable, Equatable {
        var id = UUID()
        var hour: Int
        var minute: Int
        var label: String
        var daily: Bool
        var enabled = true
        var lastFired: Date?

        var timeText: String { String(format: "%02d:%02d", hour, minute) }
    }

    @Published var alarms: [Alarm] { didSet { save(alarms, "alarms") } }

    func addAlarm(hour: Int, minute: Int, label: String, daily: Bool) {
        // 剛加的鬧鐘要從現在開始算：lastFired 設成現在，已經過了的時間今天不會補響
        alarms.append(Alarm(hour: hour, minute: minute, label: label, daily: daily, lastFired: Date()))
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    func removeAlarm(_ id: UUID) { alarms.removeAll { $0.id == id } }

    func setAlarm(_ id: UUID, enabled: Bool) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].enabled = enabled
        if enabled { alarms[i].lastFired = Date() }   // 重新打開也從現在開始算
    }

    // 從 lastFired 之後，下一次該響的時間。
    private func nextFire(_ alarm: Alarm) -> Date? {
        let after = alarm.lastFired ?? .distantPast
        return calendar.nextDate(after: after, matching: DateComponents(hour: alarm.hour, minute: alarm.minute),
                                 matchingPolicy: .nextTime)
    }

    private func checkAlarms(now: Date) {
        for i in alarms.indices where alarms[i].enabled {
            guard let fire = nextFire(alarms[i]), now >= fire else { continue }
            let alarm = alarms[i]
            alarms[i].lastFired = now
            if !alarm.daily { alarms[i].enabled = false }
            // 睡著 / 關機錯過太久（超過 10 分鐘）就不補響了
            guard now.timeIntervalSince(fire) < 10 * 60 else { continue }
            let label = alarm.label.trimmingCharacters(in: .whitespaces)
            onReminder?(Reminder(
                kind: .alarm, icon: "🔔", title: label.isEmpty ? "\(alarm.timeText) 的鬧鐘" : label,
                message: "現在 \(alarm.timeText)，別忘了喔。",
                actions: [
                    .init(title: "知道了") {},
                    .init(title: "10 分鐘後") { [weak self] in self?.startCountdown(seconds: 10 * 60, label: label.isEmpty ? "鬧鐘" : label) },
                ]))
        }
    }

    // MARK: - 行事曆

    enum CalendarAccess { case notDetermined, granted, denied }

    @Published var calendarEnabled: Bool { didSet { defaults.set(calendarEnabled, forKey: "calendarEnabled") } }
    @Published var calendarLead: Int { didSet { defaults.set(calendarLead, forKey: "calendarLead") } }
    @Published private(set) var calendarAccess: CalendarAccess = .notDetermined
    @Published private(set) var upcoming: [UpcomingEvent] = []
    private let store = EKEventStore()
    private var firedEvents: [String: Date] { didSet { save(firedEvents, "firedEvents") } }
    private var lastCalendarCheck: Date = .distantPast

    struct UpcomingEvent: Identifiable {
        let id: String
        let title: String
        let start: Date
        let location: String?
    }

    func refreshCalendarAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, *) {
            calendarAccess = status == .fullAccess ? .granted : status == .notDetermined ? .notDetermined : .denied
        } else {
            calendarAccess = status == .authorized ? .granted : status == .notDetermined ? .notDetermined : .denied
        }
    }

    // 打開行事曆提醒：還沒問過權限就跳出系統的詢問視窗。
    func enableCalendar() {
        calendarEnabled = true
        refreshCalendarAccess()
        guard calendarAccess == .notDetermined else { return checkCalendar(now: Date(), force: true) }
        let done: @Sendable (Bool, Error?) -> Void = { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshCalendarAccess()
                self?.checkCalendar(now: Date(), force: true)
            }
        }
        if #available(macOS 14, *) {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestAccess(to: .event, completion: done)
        }
    }

    private func checkCalendar(now: Date, force: Bool = false) {
        // 30 秒看一次就夠了
        guard force || now.timeIntervalSince(lastCalendarCheck) >= 30 else { return }
        lastCalendarCheck = now
        refreshCalendarAccess()
        guard calendarEnabled, calendarAccess == .granted else {
            upcoming = []
            return
        }
        // 今天接下來（最多 12 小時內）的行程，全天行程不提醒
        let end = min(calendar.startOfDay(for: now).addingTimeInterval(86_400), now.addingTimeInterval(12 * 3600))
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60), end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate >= now.addingTimeInterval(-60) }
            .sorted { $0.startDate < $1.startDate }
        upcoming = events.prefix(5).map {
            UpcomingEvent(id: Self.key($0), title: $0.title ?? "（沒有標題）", start: $0.startDate,
                          location: $0.location.flatMap { $0.isEmpty ? nil : $0 })
        }
        // 舊的紀錄清掉
        firedEvents = firedEvents.filter { now.timeIntervalSince($0.value) < 86_400 }
        for event in upcoming where firedEvents[event.id] == nil {
            let left = event.start.timeIntervalSince(now)
            guard left <= Double(calendarLead) * 60 else { continue }
            firedEvents[event.id] = now
            let minutes = Int((left / 60).rounded())
            let when = minutes <= 0 ? "現在開始" : "\(minutes) 分鐘後開始"
            let place = event.location.map { "・\($0)" } ?? ""
            onReminder?(Reminder(
                kind: .calendar, icon: "📅", title: event.title,
                message: "\(when)（\(Self.timeFormatter.string(from: event.start))\(place)）",
                actions: [.init(title: "知道了") {}]))
        }
    }

    private static func key(_ event: EKEvent) -> String {
        "\(event.calendarItemIdentifier)|\(Int(event.startDate.timeIntervalSince1970))"
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - 每秒檢查

    private let defaults = UserDefaults.standard
    private let calendar = Calendar.current
    private var timer: Timer?
    private var today: Date

    init() {
        let d = UserDefaults.standard
        focusMinutes = d.object(forKey: "focusMinutes") as? Int ?? 25
        breakMinutes = d.object(forKey: "breakMinutes") as? Int ?? 5
        longBreakMinutes = d.object(forKey: "longBreakMinutes") as? Int ?? 15
        waterEnabled = d.bool(forKey: "waterEnabled")
        waterInterval = d.object(forKey: "waterInterval") as? Int ?? 45
        calendarEnabled = d.bool(forKey: "calendarEnabled")
        calendarLead = d.object(forKey: "calendarLead") as? Int ?? 10
        soundOn = d.object(forKey: "reminderSound") as? Bool ?? true
        countdownSound = d.string(forKey: "countdownSound") ?? "Glass"
        alarmSound = d.string(forKey: "alarmSound") ?? "Funk"
        alarms = Self.load([Alarm].self, "alarms") ?? []
        firedEvents = Self.load([String: Date].self, "firedEvents") ?? [:]
        pomodoro = Self.load(PomodoroState.self, "pomodoro") ?? PomodoroState()
        countdown = Self.load(CountdownState.self, "countdown")
        today = Calendar.current.startOfDay(for: Date())
        // 今天的番茄數、喝水杯數：不是今天存的就歸零
        if let saved = d.object(forKey: "remindersDay") as? Date, Calendar.current.isDate(saved, inSameDayAs: today) {
            focusDoneToday = d.integer(forKey: "focusDoneToday")
            cupsToday = d.integer(forKey: "cupsToday")
        }
        d.set(today, forKey: "remindersDay")
        resetWater()
        refreshCalendarAccess()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        let day = calendar.startOfDay(for: now)
        if day != today {
            today = day
            focusDoneToday = 0
            cupsToday = 0
            defaults.set(0, forKey: "focusDoneToday")
            defaults.set(0, forKey: "cupsToday")
            defaults.set(day, forKey: "remindersDay")
        }
        checkPomodoro(now: now)
        checkCountdown(now: now)
        checkWater(now: now, idle: Self.secondsSinceLastInput())
        checkAlarms(now: now)
        checkCalendar(now: now)
        objectWillChange.send()   // 讓視窗裡的倒數每秒更新
        onTick?()
    }

    // 多久沒動鍵盤滑鼠（不需要任何權限）。
    static func secondsSinceLastInput() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    // MARK: - 存取

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // 選單列的圖示：專注 🍅、休息 ☕️、倒數 ⏰；都沒有就是 nil。
    var menuBarIcon: String? {
        if pomodoro.phase != .idle { return pomodoro.phase == .focus ? "🍅" : "☕️" }
        return countdown != nil ? "⏰" : nil
    }

    // 選單裡顯示的倒數，例如「🍅 專注中，還有 12:34」；沒有在倒數就是 nil。
    var menuBarText: String? {
        if let left = pomodoroLeft() {
            let what = pomodoro.phase == .focus ? "🍅 專注中" : "☕️ 休息中"
            return "\(what)，還有 \(Self.clock(left))\(pomodoro.pausedLeft != nil ? "（暫停）" : "")"
        }
        if let left = countdownLeft() {
            let label = countdown?.label.isEmpty == false ? "：\(countdown!.label)" : ""
            return "⏰ 倒數\(label)，還有 \(Self.clock(left))\(countdown?.pausedLeft != nil ? "（暫停）" : "")"
        }
        return nil
    }

    // 「1 小時 5 分 30 秒」這種說法（0 的部分省略）。
    static func durationText(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        var parts: [String] = []
        if s >= 3600 { parts.append("\(s / 3600) 小時") }
        if s / 60 % 60 > 0 { parts.append("\(s / 60 % 60) 分") }
        if s % 60 > 0 || parts.isEmpty { parts.append("\(s % 60) 秒") }
        return parts.joined(separator: " ")
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - 鈴聲

// 倒數、鬧鐘時間到的鈴聲：選好的系統音效「叮、叮——停一下」一直重複，直到 stop()。
// 試聽也用它（響幾秒就自己停）。同一時間只會有一個鈴聲在響。
@MainActor
final class Ringer: ObservableObject {
    static let shared = Ringer()

    // 可以選的鈴聲：macOS 內建的系統音效（/System/Library/Sounds）。"" = 不響。
    static let sounds = ["Glass", "Funk", "Hero", "Ping", "Submarine", "Blow", "Bottle", "Frog", "Morse", "Pop", "Purr", "Sosumi", "Tink", "Basso"]
    static let maxRing: Double = 3 * 60   // 一直沒人按也最多響 3 分鐘

    @Published private(set) var previewing: String?   // 正在試聽的鈴聲

    private var timer: Timer?
    private var step = 0
    private var playing: NSSound?
    private var stopAt = Date.distantPast

    func ring(_ name: String) {
        start(name, for: Self.maxRing)
        previewing = nil
    }

    // 試聽：響 4 秒；再按一次就停。
    func togglePreview(_ name: String) {
        if previewing == name { stop(); return }
        start(name, for: 4)
        previewing = name
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        playing?.stop()
        playing = nil
        previewing = nil
    }

    private func start(_ name: String, for seconds: Double) {
        stop()
        guard !name.isEmpty, let sound = NSSound(named: name) else { return }
        step = 0
        stopAt = Date().addingTimeInterval(seconds)
        // 每 0.22 秒一格：前 4 格連續響（嘟、嘟、嘟、嘟），之後安靜 3 格，一輪約 1.5 秒。
        // 響下一聲前先停掉上一聲，長一點的音效才不會疊成一團。
        let timer = Timer(timeInterval: 0.22, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Date() >= self.stopAt { self.stop(); return }
                if self.step % 7 < 4, let s = sound.copy() as? NSSound {
                    self.playing?.stop()
                    s.volume = 0.7
                    s.play()
                    self.playing = s
                }
                self.step += 1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        timer.fire()
    }
}
