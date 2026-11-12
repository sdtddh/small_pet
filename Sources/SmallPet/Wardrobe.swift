// Wardrobe.swift —— 記錄寵物目前穿什麼，並提供「衣櫃」視窗。
//
// 每個部位（手上、頭、臉、脖子、背後）同時只能穿一件；選擇會存在 UserDefaults，下次開啟還在。
import AppKit
import SwiftUI

@MainActor
final class Wardrobe: ObservableObject {

    private static let defaultsKey = "equippedOutfits"

    // 部位 id → 服裝 id。
    @Published private(set) var equipped: [String: String]

    // 換裝時通知寵物重畫。
    var onChange: (() -> Void)?

    let sprites: SpriteLibrary
    let stats: PetStats

    init(sprites: SpriteLibrary, stats: PetStats) {
        self.sprites = sprites
        self.stats = stats
        let saved = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        // 過濾掉已經不存在的服裝（例如素材被刪掉了）。
        let valid = Set(sprites.manifest.outfits.map(\.id))
        equipped = saved.filter { valid.contains($0.value) }
    }

    // 衣櫃裡看得到的服裝：一般服裝 + 從地下城拿到的服裝。
    func available(in slot: String) -> [Manifest.Outfit] {
        sprites.outfits(in: slot).filter { $0.dungeon != true || stats.owns($0.id) }
    }

    // 身上服裝的戰鬥力加成總和。
    var powerBonus: Int {
        equipped.values.reduce(0) { sum, id in
            sum + (sprites.manifest.outfits.first { $0.id == id }?.power ?? 0)
        }
    }

    // outfitID 傳 nil 代表脫掉這個部位。
    func equip(_ outfitID: String?, slot: String) {
        equipped[slot] = outfitID
        UserDefaults.standard.set(equipped, forKey: Self.defaultsKey)
        onChange?()
    }
}

// MARK: - 衣櫃視窗

@MainActor
final class WardrobeWindowController {

    private var window: NSWindow?
    private let wardrobe: Wardrobe

    init(wardrobe: Wardrobe) {
        self.wardrobe = wardrobe
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "衣櫃"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: WardrobeView(wardrobe: wardrobe, stats: wardrobe.stats))
            w.center()
            window = w
        }
        // 我們是 .accessory App（沒有 Dock 圖示），要主動把視窗叫到前面。
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WardrobeView: View {
    @ObservedObject var wardrobe: Wardrobe
    @ObservedObject var stats: PetStats

    private var sprites: SpriteLibrary { wardrobe.sprites }

    var body: some View {
        VStack(spacing: 16) {
            // 大預覽：目前的穿搭
            PetPreview(sprites: sprites, outfits: wardrobe.equipped)
                .frame(width: 140, height: 140)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 由上往下顯示：手上 → 頭 → 臉 → 脖子 → 背後（manifest 裡是疊圖順序，所以反過來）
                    ForEach(sprites.manifest.slots.reversed()) { slot in
                        slotRow(slot)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .frame(minWidth: 420, minHeight: 600)
    }

    private func slotRow(_ slot: Manifest.Slot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(slot.name).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    option(name: "無", outfitID: nil, slot: slot.id)
                    ForEach(wardrobe.available(in: slot.id)) { outfit in
                        option(name: outfit.power.map { $0 > 0 ? "\(outfit.name) +\($0)" : outfit.name } ?? outfit.name,
                               outfitID: outfit.id, slot: slot.id)
                    }
                }
            }
        }
    }

    private func option(name: String, outfitID: String?, slot: String) -> some View {
        let selected = wardrobe.equipped[slot] == outfitID
        // 縮圖：目前其他部位的穿搭 + 換上這一件
        var preview = wardrobe.equipped
        preview[slot] = outfitID

        return Button {
            wardrobe.equip(outfitID, slot: slot)
        } label: {
            VStack(spacing: 4) {
                PetPreview(sprites: sprites, outfits: preview)
                    .frame(width: 64, height: 64)
                Text(name).font(.caption)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// 把本體和服裝疊起來的靜態預覽（使用 idle 第 0 格）。
struct PetPreview: View {
    let sprites: SpriteLibrary
    let outfits: [String: String]

    var body: some View {
        ZStack {
            if let body = sprites.bodyFrame(.idle, 0) {
                Image(nsImage: body).resizable().scaledToFit()
            }
            ForEach(sprites.manifest.slots) { slot in
                if let id = outfits[slot.id], let image = sprites.outfitFrame(id, .idle, 0) {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            }
        }
    }
}
