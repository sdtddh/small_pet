// ReminderWindow.swift —— 提醒的樣子：
//   ReminderCardController：時間到時在她旁邊浮出的小卡片（不搶焦點，按一下按鈕就收起來）。
//   RemindersWindowController：「提醒」設定視窗——番茄鐘、倒數計時、喝水、鬧鐘與行事曆。
import AppKit
import SwiftUI

// MARK: - 小卡片

@MainActor
final class ReminderCardController {

    private var panel: NSPanel?
    private var queue: [Reminder] = []
    private var showing = false
    private var generation = 0

    // 卡片要擺在哪：回傳她的視窗位置；她不在畫面上（出門、藏起來）就回傳 nil，卡片放右下角。
    var anchor: () -> NSRect? = { nil }

    func show(_ reminder: Reminder) {
        queue.append(reminder)
        if !showing { showNext() }
    }

    private func showNext() {
        guard !queue.isEmpty else {
            showing = false
            return
        }
        showing = true
        generation += 1
        let current = generation
        let reminder = queue.removeFirst()

        let panel = makePanel()
        let card = ReminderCardView(reminder: reminder) { [weak self] action in
            action?.run()
            self?.dismiss(generation: current)
        }
        let host = NSHostingView(rootView: card)
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        place(panel)

        // 輕輕浮上來
        panel.alphaValue = 0
        let target = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: target.x, y: target.y - 10))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(target)
        }

        if let seconds = reminder.autoDismiss {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.dismiss(generation: current)
            }
        }
    }

    private func dismiss(generation expected: Int) {
        guard expected == generation, let panel else { return }
        generation += 1
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                self?.showNext()
            }
        })
    }

    private func makePanel() -> NSPanel {
        if let panel { return panel }
        // nonactivatingPanel：點卡片上的按鈕不會把 SmallPet 叫到前面、不會打斷你正在打字的 App
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isExcludedFromWindowsMenu = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        panel = p
        return p
    }

    // 她旁邊（右邊放不下就放左邊）；她不在畫面上就放在螢幕右下角。
    private func place(_ panel: NSPanel) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        var origin: NSPoint
        if let pet = anchor() {
            let right = pet.maxX - 8
            let x = right + size.width <= visible.maxX ? right : pet.minX + 8 - size.width
            origin = NSPoint(x: x, y: pet.minY + pet.height * 0.45)
        } else {
            origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.minY + 16)
        }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        panel.setFrameOrigin(origin)
    }
}

private struct ReminderCardView: View {
    let reminder: Reminder
    let onTap: (Reminder.Action?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(reminder.icon).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title).font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reminder.message).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Spacer()
                let actions = reminder.actions.isEmpty ? [Reminder.Action(title: "好") {}] : reminder.actions
                ForEach(Array(actions.enumerated()), id: \.offset) { i, action in
                    if i == 0 {
                        Button(action.title) { onTap(action) }.buttonStyle(.borderedProminent).controlSize(.small)
                    } else {
                        Button(action.title) { onTap(action) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 250)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
        .padding(4)
    }
}

// MARK: - 設定視窗

@MainActor
final class RemindersWindowController {

    private var window: NSWindow?
    private let center: ReminderCenter
    private let nav = RemindersNav()

    init(center: ReminderCenter) {
        self.center = center
    }

    // tab：要打開哪一頁（nil = 上次那頁）；above：時鐘的位置，視窗開在它正上方（nil = 螢幕中間）。
    func show(tab: RemindersNav.Tab? = nil, above anchor: NSRect? = nil) {
        if let tab { nav.tab = tab }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 470),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "生活與專注提醒"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: RemindersView(center: center, nav: nav))
            w.center()
            window = w
        }
        if let anchor, let window, let visible = NSScreen.main?.visibleFrame {
            let size = window.frame.size
            let x = min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width)
            let y = min(anchor.maxY + 8, visible.maxY - size.height)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        center.refreshCalendarAccess()
        window?.bringToFront()
    }
}

// 設定視窗現在在哪一頁（從時鐘打開時直接跳到番茄鐘）。
@MainActor
final class RemindersNav: ObservableObject {
    enum Tab: Hashable { case pomodoro, countdown, water, alarm, look }
    @Published var tab = Tab.pomodoro
}

struct RemindersView: View {
    @ObservedObject var center: ReminderCenter
    @ObservedObject var nav: RemindersNav
    @State private var countdownMinutes = 10
    @State private var countdownLabel = ""
    @State private var alarmTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var alarmLabel = ""
    @State private var alarmDaily = false
    @AppStorage(ClockLook.key) private var clockLook = ClockLook.current

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $nav.tab) {
                pomodoroTab.tabItem { Text("番茄鐘") }.tag(RemindersNav.Tab.pomodoro)
                countdownTab.tabItem { Text("倒數") }.tag(RemindersNav.Tab.countdown)
                waterTab.tabItem { Text("喝水") }.tag(RemindersNav.Tab.water)
                alarmTab.tabItem { Text("鬧鐘・行事曆") }.tag(RemindersNav.Tab.alarm)
                lookTab.tabItem { Text("外觀") }.tag(RemindersNav.Tab.look)
            }
            Toggle("提醒時輕輕響一聲", isOn: $center.soundOn).font(.callout)
        }
        .padding()
        .frame(width: 380, height: 470)
    }

    // MARK: 外觀

    // 時鐘長成哪種植物：點圖就換，桌面上的時鐘馬上跟著變。
    private var lookTab: some View {
        VStack(spacing: 16) {
            Text("時鐘的外觀").font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                ForEach(ClockLook.allCases) { look in
                    Button {
                        clockLook = look
                        NotificationCenter.default.post(name: ClockLook.didChange, object: nil)
                    } label: {
                        VStack(spacing: 8) {
                            ClockLookPreview(look: look)
                                .frame(width: 110, height: 110)
                            Text(look.title).font(.callout.weight(clockLook == look ? .semibold : .regular))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(clockLook == look ? Color.accentColor.opacity(0.15) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(clockLook == look ? Color.accentColor : Color.secondary.opacity(0.3),
                                    lineWidth: clockLook == look ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("她澆水時會走到植物旁邊，水落在土或草地上。").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 16)
    }

    // MARK: 番茄鐘

    private var pomodoroTab: some View {
        VStack(spacing: 14) {
            let phase = center.pomodoro.phase
            let left = center.pomodoroLeft()
            Text(phase == .focus ? "專注中" : phase == .idle ? "準備開始" : phase == .longBreak ? "長休息" : "休息中")
                .font(.headline).foregroundStyle(.secondary)
            Text(ReminderCenter.clock(left ?? Double(center.focusMinutes) * 60))
                .font(.system(size: 52, weight: .semibold, design: .rounded).monospacedDigit())
            if let left, let total = phaseTotal(phase), total > 0 {
                ProgressView(value: 1 - left / total).padding(.horizontal, 30)
            }

            HStack {
                if phase == .idle {
                    Button("開始專注") { center.startFocus() }.keyboardShortcut(.defaultAction)
                } else {
                    Button(center.pomodoro.pausedLeft == nil ? "暫停" : "繼續") { center.togglePausePomodoro() }
                    if phase != .focus {
                        Button("跳過休息") { center.startFocus() }
                    }
                    Button("結束") { center.stopPomodoro() }
                }
            }

            Text("今天完成 \(center.focusDoneToday) 個番茄" + (center.focusDoneToday > 0 ? " " + String(repeating: "🍅", count: min(center.focusDoneToday, 8)) : ""))
                .font(.callout)

            Divider()
            Form {
                Stepper("專注 \(center.focusMinutes) 分鐘", value: $center.focusMinutes, in: 5...90, step: 5)
                Stepper("休息 \(center.breakMinutes) 分鐘", value: $center.breakMinutes, in: 1...30)
                Stepper("每 4 輪長休息 \(center.longBreakMinutes) 分鐘", value: $center.longBreakMinutes, in: 5...60, step: 5)
            }
            Text("專注時她會安靜一點，不會自己碎念；時間到了她會在旁邊提醒你休息。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private func phaseTotal(_ phase: ReminderCenter.PomodoroPhase) -> Double? {
        switch phase {
        case .focus: Double(center.focusMinutes) * 60
        case .shortBreak: Double(center.breakMinutes) * 60
        case .longBreak: Double(center.longBreakMinutes) * 60
        case .idle: nil
        }
    }

    // MARK: 倒數

    private var countdownTab: some View {
        VStack(spacing: 14) {
            if let c = center.countdown, let left = center.countdownLeft() {
                Text(c.label.isEmpty ? "倒數中" : c.label).font(.headline).foregroundStyle(.secondary)
                Text(ReminderCenter.clock(left))
                    .font(.system(size: 52, weight: .semibold, design: .rounded).monospacedDigit())
                ProgressView(value: 1 - left / max(c.total, 1)).padding(.horizontal, 30)
                HStack {
                    Button(c.pausedLeft == nil ? "暫停" : "繼續") { center.togglePauseCountdown() }
                    Button("取消") { center.cancelCountdown() }
                }
            } else {
                Text("要倒數多久？").font(.headline)
                HStack {
                    ForEach([3, 5, 10, 15, 30], id: \.self) { m in
                        Button("\(m) 分") { center.startCountdown(minutes: Double(m), label: countdownLabel) }
                    }
                }
                Form {
                    Stepper("自訂 \(countdownMinutes) 分鐘", value: $countdownMinutes, in: 1...240)
                    TextField("要提醒什麼（可以不填）", text: $countdownLabel)
                }
                Button("開始倒數") { center.startCountdown(minutes: Double(countdownMinutes), label: countdownLabel) }
                    .keyboardShortcut(.defaultAction)
                Text("例如泡麵 3 分鐘、曬衣服、等洗衣機。時間到她會在旁邊提醒你。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // MARK: 喝水

    private var waterTab: some View {
        VStack(spacing: 14) {
            Text("💧 今天喝了 \(center.cupsToday) 杯").font(.title2.bold())
            Text(String(repeating: "💧", count: min(center.cupsToday, 10)) + String(repeating: "・", count: max(0, 8 - center.cupsToday)))
                .font(.title3)
            Button("喝了一杯") { center.drankWater() }

            Divider()
            Form {
                Toggle("定時提醒我喝水", isOn: $center.waterEnabled)
                Stepper("每 \(center.waterInterval) 分鐘", value: $center.waterInterval, in: 15...180, step: 15)
                    .disabled(!center.waterEnabled)
            }
            if center.waterEnabled, let next = center.nextWaterAt {
                Text("下次提醒大約在 \(ReminderCenter.timeFormatter.string(from: next))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("你離開電腦超過 5 分鐘（沒動鍵盤滑鼠）就不會提醒，回來後重新計時。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // MARK: 鬧鐘・行事曆

    private var alarmTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("鬧鐘").font(.headline)
                HStack {
                    DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute).labelsHidden()
                    TextField("要做什麼", text: $alarmLabel)
                }
                HStack {
                    Toggle("每天", isOn: $alarmDaily)
                    Spacer()
                    Button("新增鬧鐘") {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
                        center.addAlarm(hour: c.hour ?? 0, minute: c.minute ?? 0, label: alarmLabel, daily: alarmDaily)
                        alarmLabel = ""
                    }
                }
                if center.alarms.isEmpty {
                    Text("還沒有鬧鐘。").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(center.alarms) { alarm in
                    HStack {
                        Toggle("", isOn: Binding(get: { alarm.enabled }, set: { center.setAlarm(alarm.id, enabled: $0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        Text(alarm.timeText).font(.body.monospacedDigit().bold())
                        Text(alarm.label.isEmpty ? "鬧鐘" : alarm.label).lineLimit(1)
                        if alarm.daily { Text("每天").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button { center.removeAlarm(alarm.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    .opacity(alarm.enabled ? 1 : 0.5)
                }

                Divider()
                Text("行事曆").font(.headline)
                Toggle("行程開始前提醒我", isOn: Binding(
                    get: { center.calendarEnabled },
                    set: { $0 ? center.enableCalendar() : (center.calendarEnabled = false) }))
                Stepper("提前 \(center.calendarLead) 分鐘", value: $center.calendarLead, in: 0...60, step: 5)
                    .disabled(!center.calendarEnabled)
                if center.calendarEnabled {
                    switch center.calendarAccess {
                    case .granted:
                        if center.upcoming.isEmpty {
                            Text("今天接下來沒有行程。").font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(center.upcoming) { e in
                            HStack {
                                Text(ReminderCenter.timeFormatter.string(from: e.start)).font(.callout.monospacedDigit().bold())
                                Text(e.title).font(.callout).lineLimit(1)
                            }
                        }
                    case .denied:
                        Text("沒有行事曆的權限。到「系統設定 → 隱私權與安全性 → 行事曆」允許 SmallPet。")
                            .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        Button("前往設定…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    case .notDetermined:
                        Text("等待權限…").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("讀取「行事曆」App 裡今天的行程（包含 iCloud、Google 等已加入的帳號），只看時間和標題，不會修改。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
        }
    }
}

// 外觀分頁裡的小圖：直接用 App 裡那張時鐘圖。
private struct ClockLookPreview: View {
    let look: ClockLook

    var body: some View {
        if let image = SpriteLibrary.propImage(look.propName) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            Text(look.title)
        }
    }
}
