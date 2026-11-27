// VocabWindow.swift —— 背單字的兩種畫面：
//   VocabCardController：浮在寵物旁邊的 Anki 翻卡小面板＆當日未學習提醒面板（nonactivatingPanel，點擊不搶焦點）。
//   VocabWindowController：「單字本」視窗——學習（Anki 翻卡）、詞庫（開關詞書 / 新增 / CSV・Anki 匯入匯出）、設定。
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 共用四階熟練度按鈕列（Anki 風格：上方顯示下次間隔、下方顯示熟練度）

private struct AnkiRatingBar: View {
    @ObservedObject var center: VocabCenter
    var compact = false
    var enableShortcuts = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            ForEach(VocabRating.allCases) { rating in
                ratingButton(rating)
            }
        }
    }

    @ViewBuilder
    private func ratingButton(_ rating: VocabRating) -> some View {
        let interval = center.previewInterval(for: rating)
        let tint = Self.tint(for: rating)
        let btn = Button {
            center.grade(rating)
        } label: {
            VStack(spacing: 2) {
                Text(interval)
                    .font(.system(size: compact ? 10.5 : 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(enableShortcuts ? "\(rating.keyNumber)・\(rating.title)" : rating.title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 6 : 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if enableShortcuts {
            btn.keyboardShortcut(KeyEquivalent(Swift.Character("\(rating.keyNumber)")), modifiers: [])
        } else {
            btn
        }
    }

    private static func tint(for rating: VocabRating) -> Color {
        switch rating {
        case .again: .red
        case .hard:  .orange
        case .good:  .blue
        case .easy:  .green
        }
    }
}

// MARK: - 桌面陪伴小面板（不搶焦點）

@MainActor
final class VocabCardController {

    enum Mode { case study, unstudiedReminder }

    private var panel: NSPanel?
    private let center: VocabCenter
    private var mode: Mode = .study
    private var visible = false
    private var changeWatcher: AnyCancellable?

    // 回傳寵物的視窗位置；不在畫面上時回傳 nil（改放螢幕右下角）。
    var anchor: () -> NSRect? = { nil }
    var onOpenWindow: (() -> Void)?

    init(center: VocabCenter) {
        self.center = center
        // 內容變了（翻開答案、評分、在單字本視窗裡背…）就重新量高度。
        // objectWillChange 在值改變「之前」送出，所以等下一輪 SwiftUI 更新完再量。
        changeWatcher = center.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fitToContent() }
        }
    }

    var isVisible: Bool { visible && panel?.isVisible == true }

    func showStudy() {
        center.rebuildQueue()
        present(mode: .study)
    }

    func showUnstudiedReminder() {
        present(mode: .unstudiedReminder)
    }

    func hide() {
        guard let panel, visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.visible else { return }
                panel.orderOut(nil)
            }
        })
    }

    // 寵物移動時跟著移動。
    func follow(_ petFrame: NSRect) {
        guard isVisible, let panel else { return }
        place(panel, petFrame: petFrame)
    }

    private func present(mode: Mode) {
        self.mode = mode
        let wasVisible = isVisible
        visible = true
        let panel = makePanel()
        refreshContent(on: panel)
        place(panel, petFrame: anchor())

        if !wasVisible {
            panel.alphaValue = 0
            let target = panel.frame.origin
            panel.setFrameOrigin(NSPoint(x: target.x, y: target.y - 8))
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(target)
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    private func refreshLayout() {
        guard let panel, visible else { return }
        refreshContent(on: panel)
        place(panel, petFrame: anchor())
    }

    // 只調整大小與位置，不重建畫面。
    private func fitToContent() {
        guard let panel, visible, let host = panel.contentView else { return }
        let fitting = host.fittingSize
        guard fitting != panel.frame.size else { return }
        panel.setContentSize(fitting)
        place(panel, petFrame: anchor())
    }

    private func refreshContent(on panel: NSPanel) {
        let root = VocabFloatingCardView(
            center: center,
            mode: mode,
            onSwitchToStudy: { [weak self] in
                guard let self else { return }
                self.center.rebuildQueue()
                self.mode = .study
                self.refreshLayout()
            },
            onOpenBook: { [weak self] in
                self?.hide()
                self?.onOpenWindow?()
            },
            onClose: { [weak self] in self?.hide() }
        )
        let host = NSHostingView(rootView: root)
        let fitting = host.fittingSize
        host.frame.size = fitting
        panel.contentView = host
        panel.setContentSize(fitting)
    }

    private func makePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 140),
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

    private func place(_ panel: NSPanel, petFrame: NSRect?) {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        var origin: NSPoint
        if let pet = petFrame {
            let right = pet.maxX - 4
            let x = right + size.width <= visibleFrame.maxX ? right : pet.minX + 4 - size.width
            origin = NSPoint(x: x, y: pet.minY + pet.height * 0.35)
        } else {
            origin = NSPoint(x: visibleFrame.maxX - size.width - 16, y: visibleFrame.minY + 16)
        }
        origin.x = min(max(origin.x, visibleFrame.minX + 6), visibleFrame.maxX - size.width - 6)
        origin.y = min(max(origin.y, visibleFrame.minY + 6), visibleFrame.maxY - size.height - 6)
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }
}

private struct VocabFloatingCardView: View {
    @ObservedObject var center: VocabCenter
    let mode: VocabCardController.Mode
    let onSwitchToStudy: () -> Void
    let onOpenBook: () -> Void
    let onClose: () -> Void

    var body: some View {
        Group {
            switch mode {
            case .unstudiedReminder:
                reminderBody
            case .study:
                studyBody
            }
        }
        .padding(12)
        .frame(width: 286)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.09)))
        .padding(4)
    }

    private var reminderBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text("📚").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 3) {
                    Text("今天還沒背單字喔")
                        .font(.system(size: 13, weight: .semibold))
                    Text("今日目標 0 / \(center.dailyGoal) 字。要在旁邊順手翻幾張卡，還是打開單字本？")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Spacer()
                Button("今天先跳過", action: onClose)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                Button("開單字本", action: onOpenBook)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                Button("就在旁邊背", action: onSwitchToStudy)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var studyBody: some View {
        if let word = center.currentWord {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(word.word)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)
                            if !word.pos.isEmpty {
                                Text(word.pos)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.14)))
                            }
                        }
                        if !word.phonetic.isEmpty {
                            Text(word.phonetic)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Text("\(center.studiedToday)/\(center.dailyGoal)")
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                    Button {
                        center.speakCurrent()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .padding(5)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("朗讀單字發音")
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                    .help("收起小卡")
                }

                if !center.revealed {
                    Button {
                        center.reveal()
                    } label: {
                        Text("顯示答案")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(word.meaning)
                            .font(.system(size: 13, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if !word.example.isEmpty {
                            Text(word.example)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    AnkiRatingBar(center: center, compact: true, enableShortcuts: false)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("🎉").font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日佇列都複習完了！")
                            .font(.system(size: 13, weight: .semibold))
                        Text("今天已學 \(center.studiedToday) 字・連續 \(max(center.streak, 1)) 天 🔥")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    Spacer()
                    if center.counts.new > 0 {
                        Button("再背 10 個") {
                            center.loadMoreNewWords(count: 10)
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                    Button("打開單字本", action: onOpenBook)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    Button("收起", action: onClose)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

// MARK: - 「單字本」視窗

@MainActor
final class VocabWindowController {

    private var window: NSWindow?
    private let center: VocabCenter
    private let stats: PetStats
    private let nav = VocabNav()

    init(center: VocabCenter, stats: PetStats) {
        self.center = center
        self.stats = stats
    }

    func show(tab: VocabNav.Tab? = nil, above anchor: NSRect? = nil) {
        if let tab { nav.tab = tab }
        center.rebuildQueue()
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "單字本"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: VocabWindowView(center: center, stats: stats, nav: nav))
            w.center()
            window = w
        }
        if let anchor, let window, !window.isVisible, let visible = NSScreen.main?.visibleFrame {
            let size = window.frame.size
            let x = min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width)
            let y = min(anchor.maxY + 8, visible.maxY - size.height)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        window?.bringToFront()
    }
}

@MainActor
final class VocabNav: ObservableObject {
    enum Tab: String, CaseIterable, Hashable {
        case study, decks, settings
        var title: String {
            switch self {
            case .study: "學習"
            case .decks: "詞庫"
            case .settings: "設定"
            }
        }
    }
    @Published var tab: Tab = .study
}

struct VocabWindowView: View {
    @ObservedObject var center: VocabCenter
    @ObservedObject var stats: PetStats
    @ObservedObject var nav: VocabNav

    @State private var searchText = ""
    @State private var selectedDeckFilter = "all"
    @State private var showingAddForm = false
    @State private var newWord = ""
    @State private var newPhonetic = ""
    @State private var newPos = ""
    @State private var newMeaning = ""
    @State private var newExample = ""
    @State private var importBanner: String?

    var body: some View {
        VStack(spacing: 10) {
            topBar
            Group {
                switch nav.tab {
                case .study: studyTab
                case .decks: decksTab
                case .settings: settingsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
        }
        .padding(14)
        .frame(width: 440, height: 540)
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(VocabNav.Tab.allCases, id: \.self) { tab in
                    Text(tab.title)
                        .font(.callout.weight(nav.tab == tab ? .semibold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(nav.tab == tab ? Color.accentColor.opacity(0.18) : Color.clear))
                        .foregroundStyle(nav.tab == tab ? Color.accentColor : Color.primary)
                        .contentShape(Rectangle())
                        .onTapGesture { nav.tab = tab }
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))

            Spacer()

            HStack(spacing: 8) {
                if center.streak > 0 {
                    Text("🔥 \(center.streak) 天")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text("🎯 今日 \(center.studiedToday) / \(center.dailyGoal)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
        }
    }

    // MARK: - 分頁 1：學習（純 Anki 翻卡）

    private var studyTab: some View {
        let c = center.counts
        return VStack(spacing: 12) {
            // 上方計數與每日養成獎勵狀態
            HStack {
                HStack(spacing: 10) {
                    Text("新詞 \(c.new)").foregroundStyle(.blue)
                    Text("學習中 \(c.learning)").foregroundStyle(.orange)
                    Text("待複習 \(c.due)").foregroundStyle(.green)
                }
                .font(.caption.weight(.semibold))
                Spacer()
                if stats.studiedRewardClaimedToday {
                    Label("今日獎勵已領（+\(PetStats.xpPerStudyGoal) XP & 🍪）", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("達標領 +\(PetStats.xpPerStudyGoal) XP & 🍪 零食 ×1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: Double(min(center.studiedToday, center.dailyGoal)),
                         total: Double(max(center.dailyGoal, 1)))

            if let word = center.currentWord {
                // 閃卡主體
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(word.word)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                        if !word.pos.isEmpty {
                            Text(word.pos)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.14)))
                        }
                        Button {
                            center.speakCurrent()
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut("p", modifiers: [])
                        .help("朗讀單字（快捷鍵 P）")
                    }

                    if !word.phonetic.isEmpty {
                        Text(word.phonetic)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    if center.revealed {
                        Divider().padding(.vertical, 6)
                        VStack(spacing: 8) {
                            Text(word.meaning)
                                .font(.system(size: 18, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            if !word.example.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(word.example)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                    Button {
                                        VocabSpeaker.shared.speak(word.example, lang: word.lang)
                                    } label: {
                                        Image(systemName: "speaker.wave.1")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .help("朗讀例句")
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                    } else {
                        Text("在心裡回想意思後，點下方按鈕或按空白鍵翻開")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 14)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture {
                    if !center.revealed { center.reveal() }
                }

                // 底部操作列
                if !center.revealed {
                    Button {
                        center.reveal()
                    } label: {
                        Text("顯示答案（空白鍵）")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                } else {
                    AnkiRatingBar(center: center, compact: false, enableShortcuts: true)
                    Text("快捷鍵：1 重來・2 困難・3 良好・4 簡單・P 發音")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                // 完成或尚未啟用詞書
                VStack(spacing: 12) {
                    Spacer()
                    if center.enabledWords.isEmpty {
                        Text("📚").font(.system(size: 40))
                        Text("目前沒有啟用的詞書")
                            .font(.title3.bold())
                        Text("到「詞庫」分頁勾選想背的詞書，或匯入自己的單字檔吧！")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("前往詞庫") { nav.tab = .decks }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text("🎉").font(.system(size: 42))
                        Text("今天的學習佇列完成囉！")
                            .font(.title3.bold())
                        Text("今日已複習 \(center.studiedToday) 個單字，明天也繼續保持吧～")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if c.new > 0 {
                            Button("再多背 10 個新單字（剩餘 \(c.new) 個新詞）") {
                                center.loadMoreNewWords(count: 10)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 分頁 2：詞庫管理與匯入匯出

    private var decksTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("啟用詞書").font(.headline)
                Spacer()
                Button {
                    showingAddForm.toggle()
                } label: {
                    Label(showingAddForm ? "收起表單" : "新增單字", systemImage: showingAddForm ? "chevron.up" : "plus")
                }
                .controlSize(.small)
                Button("匯入 CSV / Anki…", action: importFromFile)
                    .controlSize(.small)
                Button("匯出 TSV…", action: exportToFile)
                    .controlSize(.small)
            }

            if let banner = importBanner {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(banner).font(.caption)
                    Spacer()
                    Button { importBanner = nil } label: { Image(systemName: "xmark").font(.caption2) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
            }

            // 新增自訂單字摺疊表單
            if showingAddForm {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("單字（必填）", text: $newWord)
                        TextField("音標（選填）", text: $newPhonetic).frame(width: 110)
                        TextField("詞性", text: $newPos).frame(width: 64)
                    }
                    TextField("中文解釋（必填）", text: $newMeaning)
                    HStack(spacing: 6) {
                        TextField("例句（選填）", text: $newExample)
                        Button("加入") {
                            if center.addCustomWord(word: newWord, phonetic: newPhonetic, pos: newPos,
                                                    meaning: newMeaning, example: newExample) {
                                newWord = ""; newPhonetic = ""; newPos = ""; newMeaning = ""; newExample = ""
                                importBanner = "已加入自訂詞庫！"
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  newMeaning.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            }

            // 詞書勾選列
            VStack(spacing: 5) {
                ForEach(center.allDecks) { deck in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { center.isDeckEnabled(deck.id) },
                            set: { center.setDeck(deck.id, enabled: $0) }
                        ))
                        .labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(deck.name).font(.callout.weight(.semibold))
                            Text(deck.description).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("已學 \(center.learnedCount(in: deck)) / \(deck.words.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor).opacity(0.75)))
                }
            }

            // 搜尋與篩選
            HStack(spacing: 6) {
                TextField("搜尋單字或解釋…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $selectedDeckFilter) {
                    Text("全部啟用").tag("all")
                    ForEach(center.allDecks) { d in
                        Text(d.name).tag(d.id)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            // 單字清單
            ScrollView {
                LazyVStack(spacing: 4) {
                    let list = filteredWords
                    if list.isEmpty {
                        Text("找不到符合的單字").font(.callout).foregroundStyle(.secondary).padding(.top, 20)
                    }
                    ForEach(list) { word in
                        wordRow(word)
                    }
                }
            }
        }
    }

    private var filteredWords: [VocabWord] {
        let base: [VocabWord]
        if selectedDeckFilter == "all" {
            base = center.enabledWords
        } else {
            base = center.allDecks.first(where: { $0.id == selectedDeckFilter })?.words ?? []
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.word.lowercased().contains(q) || $0.meaning.lowercased().contains(q)
        }
    }

    private func wordRow(_ word: VocabWord) -> some View {
        let p = center.progress(for: word)
        return HStack(spacing: 8) {
            Button {
                VocabSpeaker.shared.speak(word.word, lang: word.lang)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(word.word).font(.callout.weight(.semibold))
                    if !word.pos.isEmpty {
                        Text(word.pos).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(word.meaning).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            stageBadge(p)
            if word.deckID == VocabDeck.customID {
                Button {
                    center.deleteCustomWord(word.id)
                } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("刪除此自訂單字")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
        .contextMenu {
            if p != nil {
                Button("重置熟練度（變回新詞）") { center.resetProgress(for: word.id) }
            }
            if word.deckID == VocabDeck.customID {
                Button("刪除單字", role: .destructive) { center.deleteCustomWord(word.id) }
            }
        }
    }

    @ViewBuilder
    private func stageBadge(_ p: VocabProgress?) -> some View {
        if let p {
            switch p.stage {
            case .learning:
                Text("學習中")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.16)))
                    .foregroundStyle(.orange)
            case .young:
                Text("\(p.intervalDays)天間隔")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                    .foregroundStyle(.blue)
            case .mature:
                Text("熟練・\(p.intervalDays)天")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.16)))
                    .foregroundStyle(.green)
            }
        } else {
            Text("新詞")
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                .foregroundStyle(.secondary)
        }
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.title = "匯入 CSV / TSV / Anki 單字文字檔"
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let count = center.importText(text)
        importBanner = count > 0 ? "成功匯入 \(count) 個單字！" : "沒有讀到有效的「單字, 解釋」欄位"
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.title = "匯出單字本（Anki 相容 TSV）"
        panel.nameFieldStringValue = "smallpet-vocab.tsv"
        panel.allowedContentTypes = [.tabSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = center.exportTSV(onlyCustom: false)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        importBanner = "已匯出至 \(url.lastPathComponent)"
    }

    // MARK: - 分頁 3：設定（精簡溫和版）

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: center.state.reminderHour,
                                      minute: center.state.reminderMinute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                center.setReminder(enabled: center.state.reminderEnabled,
                                   hour: c.hour ?? 20, minute: c.minute ?? 0)
            }
        )
    }

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("每日目標與養成獎勵").font(.headline)
                Stepper("每天背 \(center.dailyGoal) 個單字", value: Binding(
                    get: { center.dailyGoal },
                    set: { center.setDailyGoal($0) }
                ), in: 5...100, step: 5)
                Text("每天完成目標時，目前陪伴你的角色會獲得 +\(PetStats.xpPerStudyGoal) XP 與 🍪 零食 ×1（每天 1 次）。單字複習進度由所有角色共用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            VStack(alignment: .leading, spacing: 10) {
                Text("當日尚未學習提醒").font(.headline)
                Toggle("今天還沒背單字時，讓她提醒我", isOn: Binding(
                    get: { center.state.reminderEnabled },
                    set: { center.setReminder(enabled: $0) }
                ))
                HStack {
                    Text("提醒時間")
                    Spacer()
                    DatePicker("", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!center.state.reminderEnabled)
                }
                Text("過了設定時間若今天已學單字仍為 0、且你在電腦前（5 分鐘內有動鍵盤滑鼠），她會在旁邊溫柔提醒一次；提醒過就不再重複打擾。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            VStack(alignment: .leading, spacing: 8) {
                Text("發音").font(.headline)
                Toggle("出現單字時自動朗讀發音", isOn: Binding(
                    get: { center.state.autoSpeak },
                    set: { center.setAutoSpeak($0) }
                ))
                Text("使用 macOS 內建離線語音合成（AVSpeechSynthesizer），不需要網路或額外權限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            Spacer(minLength: 0)
        }
    }
}
