// StatusWindow.swift —— 「狀態」視窗，分四頁：
//   狀態：等級、經驗值、戰鬥力、今天還能餵幾次、「跟著我打字 / 點擊」開關
//   地下城：出門冒險、看還要多久回來
//   背包：零食、收集到的服裝、戰報
//   權限：哪些功能需要 macOS 的權限、現在有沒有給、前往設定的按鈕
import AppKit
import SwiftUI

@MainActor
final class StatusWindowController {

    private var window: NSWindow?
    private let stats: PetStats
    private let wardrobe: Wardrobe
    private let inputSync: InputSync
    private let actions: StatusActions

    init(stats: PetStats, wardrobe: Wardrobe, inputSync: InputSync,
         onFeed: @escaping () -> Void, onSnack: @escaping () -> Void,
         onStartRun: @escaping (Dungeon) -> Void, onTrial: @escaping (Dungeon) -> Void) {
        self.stats = stats
        self.wardrobe = wardrobe
        self.inputSync = inputSync
        actions = StatusActions(feed: onFeed, snack: onSnack, startRun: onStartRun, trial: onTrial)
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 650),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "狀態"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: StatusView(stats: stats, wardrobe: wardrobe, inputSync: inputSync, actions: actions))
            w.center()
            window = w
        }
        window?.bringToFront()
    }
}

extension NSWindow {
    // 我們是 .accessory App（沒有 Dock 圖示），要主動把視窗叫到前面。
    // macOS 14 起 NSApp.activate() 是「禮讓式」的：別的 App 在前面時可能被拒絕，
    // 視窗就只會開在別人後面，看起來像沒跳出來。orderFrontRegardless 不管有沒有被啟用都會蓋到最上面。
    // 從右鍵選單呼叫時選單還沒收完，所以等下一輪再做。
    func bringToFront() {
        DispatchQueue.main.async { [self] in
            if #available(macOS 14, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            makeKeyAndOrderFront(nil)
            orderFrontRegardless()
        }
    }
}

// 視窗裡的按鈕要做的事，由 AppDelegate 提供。
struct StatusActions {
    let feed: () -> Void
    let snack: () -> Void
    let startRun: (Dungeon) -> Void
    let trial: (Dungeon) -> Void      // 試打 boss：15 秒、不算次數、不存檔、不給戰利品
}

struct StatusView: View {
    @ObservedObject var stats: PetStats
    @ObservedObject var wardrobe: Wardrobe
    @ObservedObject var inputSync: InputSync
    let actions: StatusActions
    @State private var tab: Tab

    enum Tab: Hashable { case status, dungeon, bag, permissions }

    init(stats: PetStats, wardrobe: Wardrobe, inputSync: InputSync, actions: StatusActions, initialTab: Tab = .status) {
        self.stats = stats
        self.wardrobe = wardrobe
        self.inputSync = inputSync
        self.actions = actions
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        // 每秒重畫一次：冒險倒數、過了 0 點次數恢復，都靠這個更新。
        TimelineView(.periodic(from: .now, by: 1)) { context in
            TabView(selection: $tab) {
                statusTab.tabItem { Text("狀態") }.tag(Tab.status)
                dungeonTab(now: context.date).tabItem { Text("地下城") }.tag(Tab.dungeon)
                bagTab.tabItem { Text("背包") }.tag(Tab.bag)
                permissionsTab.tabItem { Text("權限") }.tag(Tab.permissions)
            }
            .padding()
            .frame(minWidth: 360, minHeight: 650)
        }
    }

    private var away: Bool { stats.run != nil }

    // MARK: 狀態

    private var statusTab: some View {
        VStack(spacing: 14) {
            PetPreview(sprites: wardrobe.sprites, outfits: wardrobe.equipped, look: wardrobe.look)
                .frame(width: 120, height: 120)
                .opacity(away ? 0.3 : 1)

            Text("Lv.\(stats.level)")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(stats.xp), total: Double(stats.xpNeeded))
                Text("XP \(stats.xp) / \(stats.xpNeeded)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 6) {
                Label("戰鬥力 \(stats.power)（等級 \(stats.level * 10) + 服裝 \(stats.outfitBonus)）", systemImage: "bolt.fill")
                Label {
                    Text("今天還能餵 \(stats.feedsLeft) 次")
                } icon: {
                    Text("🥕")
                }
            }
            .font(.callout)

            Button("餵食", action: actions.feed)
                .keyboardShortcut(.defaultAction)
                .disabled(stats.feedsLeft == 0 || away)

            Divider().padding(.horizontal, 24)
            inputSyncToggle
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // 「跟著我打字 / 點擊」開關。鍵盤沒權限時提醒一下，點了跳到「權限」頁。
    private var inputSyncToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("跟著我打字 / 點擊", isOn: Binding(get: { inputSync.enabled }, set: { inputSync.setEnabled($0) }))
                .toggleStyle(.switch)
            Text("你在任何 App 裡打字或點滑鼠，她就跟著節奏跳舞；在電腦桌前則跟著你敲鍵盤。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if inputSync.enabled, !inputSync.keyboardAllowed {
                Button { tab = .permissions } label: {
                    Label("鍵盤還沒有權限，現在只會跟著點擊。看「權限」頁…", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: 權限

    // 每秒跟著 TimelineView 重畫，所以在系統設定裡勾了之後，這裡會自己變成「已允許」。
    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SmallPet 只在你打開相關功能時才需要權限。")
                .font(.callout)
                .foregroundStyle(.secondary)

            permissionCard(
                title: "輔助使用",
                granted: inputSync.keyboardAllowed,
                features: [
                    "跟著我打字：你打字時她跟著節奏跳舞",
                    "在電腦桌前打電腦時，手跟著你的打字節奏敲鍵盤",
                ],
                note: "只偵測「有按鍵」，不會讀你打了什麼字；密碼欄位 macOS 本來就不會送出按鍵。"
                    + "允許後幾秒內就會生效，不用重開 App。"
                    + "每次重新打包 App（./make-app.sh）後簽章會變，可能要在清單裡把 SmallPet 移除再重新加入。",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("不需要權限").font(.headline)
                Label("跟著我點擊：偵測你在其他 App 點滑鼠", systemImage: "checkmark.circle")
                Label("⌥F 隱藏全部的快捷鍵", systemImage: "checkmark.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private func permissionCard(title: String, granted: Bool, features: [String], note: String, settingsURL: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                Label(granted ? "已允許" : "未允許", systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    .font(.callout.bold())
            }
            Text("影響的功能").font(.callout).foregroundStyle(.secondary)
            ForEach(features, id: \.self) { f in
                Label(f, systemImage: "keyboard").font(.callout)
            }
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("前往設定…") {
                if let url = URL(string: settingsURL) { NSWorkspace.shared.open(url) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
    }

    // MARK: 地下城

    private func dungeonTab(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let run = stats.run, let dungeon = Dungeon.find(run.dungeonID) {
                let left = max(0, Int(run.endsAt.timeIntervalSince(now)))
                Label("正在\(dungeon.name)冒險，還要 \(left / 60):\(String(format: "%02d", left % 60))",
                      systemImage: "figure.walk")
                    .font(.headline)
            } else {
                Text("今天還能出門 \(stats.runsLeft) 次・目前戰鬥力 \(stats.power)")
                    .font(.headline)
            }

            ForEach(Dungeon.all) { dungeon in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(dungeon.name)・\(dungeon.bossName)").font(.title3.bold())
                        Text("建議戰力 \(dungeon.recommendedPower)・\(Int(dungeon.minutes)) 分鐘")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("成功率 \(Int((dungeon.successChance(power: stats.power) * 100).rounded()))%")
                            .font(.callout)
                        lootLine(dungeon)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Button("出發") { actions.startRun(dungeon) }
                            .disabled(away || stats.runsLeft == 0)
                        Button("試打") { actions.trial(dungeon) }
                            .controlSize(.small)
                            .disabled(away)
                            .help("打 15 秒看看\(dungeon.bossName)：不算冒險次數、不給戰利品、不存檔")
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
            }

            Text("成功可能拿到新服裝或零食；失敗什麼都沒有。「試打」只打 15 秒看看 boss，不算次數、不給戰利品。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)   // 一定要整段換行顯示，不要被截成「…」
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // 這個地下城還剩哪些服裝沒拿到：拿過的顯示名稱，沒拿過的顯示 ???；全拿完就只會掉零食。
    // 還沒畫好的服裝（素材裡沒有）不算，因為抽到也只會給零食。
    private func lootLine(_ dungeon: Dungeon) -> some View {
        let all = wardrobe.sprites.manifest.outfits
        let outfits = dungeon.loot.compactMap { id in all.first { $0.id == id } }
        let left = outfits.filter { !stats.owns($0.id) }
        let names = outfits.enumerated().reduce(Text("")) { text, item in
            // 拿到過才知道是什麼，還沒掉過的只顯示 ???
            let owned = stats.owns(item.element.id)
            let name = Text(owned ? item.element.name : "???")
                .foregroundColor(owned ? .primary : .secondary)
            return item.offset == 0 ? name : text + Text("、").foregroundColor(.secondary) + name
        }
        // 第一行剩幾件、第二行名稱（擠在同一行時名稱會被拆開換行）
        let summary = left.isEmpty
            ? Text("掉落：全收集了，只會掉零食").foregroundColor(.secondary)
            : Text("掉落：").foregroundColor(.secondary) + Text("還差 \(left.count)/\(outfits.count) 件").foregroundColor(.orange)
        return VStack(alignment: .leading, spacing: 1) {
            summary
            names
        }
        .font(.callout)
            .help("成功時從這些服裝和零食裡抽一樣；抽到已經有的服裝就改給零食")
    }

    // MARK: 背包

    private var bagTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🍪 零食 ×\(stats.snacks)").font(.title3)
                Spacer()
                Button("吃零食", action: actions.snack)
                    .disabled(stats.snacks == 0 || away)
            }
            Text("吃零食跟餵食一樣 +\(PetStats.xpPerFeed) XP，而且不佔今天的餵食次數。")
                .font(.callout)
                .foregroundStyle(.secondary)

            let won = wardrobe.sprites.manifest.outfits.filter { stats.owns($0.id) }
            Text("地下城收集的服裝").font(.headline)
            Text(won.isEmpty ? "還沒有" : won.map(\.name).joined(separator: "、"))
                .font(.callout)
                .foregroundStyle(won.isEmpty ? .secondary : .primary)

            Text("戰報").font(.headline)
            if stats.state.log.isEmpty {
                Text("還沒有冒險紀錄").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(stats.state.log) { entry in
                            HStack(alignment: .top) {
                                Text(entry.date, format: .dateTime.month().day().hour().minute())
                                    .foregroundStyle(.secondary)
                                Text(entry.text)
                            }
                            .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}
