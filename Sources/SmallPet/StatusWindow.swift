// StatusWindow.swift —— 「狀態」視窗，分三頁：
//   狀態：等級、經驗值、戰鬥力、今天還能餵幾次
//   地下城：出門冒險、看還要多久回來
//   背包：零食、收集到的服裝、戰報
import AppKit
import SwiftUI

@MainActor
final class StatusWindowController {

    private var window: NSWindow?
    private let stats: PetStats
    private let wardrobe: Wardrobe
    private let actions: StatusActions

    init(stats: PetStats, wardrobe: Wardrobe,
         onFeed: @escaping () -> Void, onSnack: @escaping () -> Void, onStartRun: @escaping (Dungeon) -> Void) {
        self.stats = stats
        self.wardrobe = wardrobe
        actions = StatusActions(feed: onFeed, snack: onSnack, startRun: onStartRun)
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 510),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "狀態"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: StatusView(stats: stats, wardrobe: wardrobe, actions: actions))
            w.center()
            window = w
        }
        // 跟衣櫃一樣，.accessory App 要主動把視窗叫到前面。
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

// 視窗裡的按鈕要做的事，由 AppDelegate 提供。
struct StatusActions {
    let feed: () -> Void
    let snack: () -> Void
    let startRun: (Dungeon) -> Void
}

struct StatusView: View {
    @ObservedObject var stats: PetStats
    @ObservedObject var wardrobe: Wardrobe
    let actions: StatusActions

    var body: some View {
        // 每秒重畫一次：冒險倒數、過了 0 點次數恢復，都靠這個更新。
        TimelineView(.periodic(from: .now, by: 1)) { context in
            TabView {
                statusTab.tabItem { Text("狀態") }
                dungeonTab(now: context.date).tabItem { Text("地下城") }
                bagTab.tabItem { Text("背包") }
            }
            .padding()
            .frame(minWidth: 360, minHeight: 510)
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
                    .font(.caption)
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
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
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
                        Text(dungeon.name).font(.title3.bold())
                        Text("建議戰力 \(dungeon.recommendedPower)・\(Int(dungeon.minutes)) 分鐘")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("成功率 \(Int((dungeon.successChance(power: stats.power) * 100).rounded()))%")
                            .font(.caption)
                    }
                    Spacer()
                    Button("出發") { actions.startRun(dungeon) }
                        .disabled(away || stats.runsLeft == 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
            }

            Text("成功可能拿到新服裝或零食；失敗什麼都沒有。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
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
                .font(.caption)
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
                            .font(.caption)
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
