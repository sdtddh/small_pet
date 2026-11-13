// Wardrobe.swift —— 記錄寵物目前穿什麼，並提供「衣櫃」視窗。
//
// 每個部位（手上、頭、臉、脖子、背後）同時只能穿一件；選擇會存在 UserDefaults，下次開啟還在。
// 另外還有「外觀」：髮型和衣服，純粹換造型、不加戰鬥力。
import AppKit
import SwiftUI

@MainActor
final class Wardrobe: ObservableObject {

    // 每個角色各自記住穿什麼；第一個角色沿用舊的 key。
    private static let defaultsKey = Character.isOriginal ? "equippedOutfits" : "equippedOutfits.\(Character.current)"
    private static let lookKey = Character.isOriginal ? "look" : "look.\(Character.current)"
    // 衣櫃存檔的版本。沒有這個 key = 第 1 版（1.3.0 以前）。
    // 改了存檔內容要轉換時：把 currentVersion 加 1，在 migrate 裡加一段「從上一版升到這一版」。
    private static let versionKey = "wardrobeVersion.\(Character.current)"
    private static let currentVersion = 2

    // 部位 id → 服裝 id。
    @Published private(set) var equipped: [String: String]

    // 目前的髮型 + 衣服。
    @Published private(set) var look: Look

    // 換裝時通知寵物重畫。
    var onChange: (() -> Void)?

    let sprites: SpriteLibrary
    let stats: PetStats

    init(sprites: SpriteLibrary, stats: PetStats) {
        self.sprites = sprites
        self.stats = stats
        let saved = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        // 過濾掉已經不存在的服裝（例如素材被刪掉了）。
        // 也過濾掉還沒從地下城拿到的服裝。
        let valid = Set(sprites.manifest.outfits.filter { $0.dungeon != true || stats.owns($0.id) }.map(\.id))
        var equipped = saved.filter { valid.contains($0.value) }
        Self.migrate(&equipped, manifest: sprites.manifest, valid: valid)
        self.equipped = equipped

        var look = sprites.defaultLook
        let savedLook = UserDefaults.standard.dictionary(forKey: Self.lookKey) as? [String: String] ?? [:]
        if let h = savedLook["hair"], sprites.manifest.looks?.hair.contains(where: { $0.id == h }) == true { look.hair = h }
        if let c = savedLook["clothes"], sprites.manifest.looks?.clothes.contains(where: { $0.id == c }) == true { look.clothes = c }
        self.look = look
    }

    // 把舊版存檔一版一版升到 currentVersion，升完存回去。
    private static func migrate(_ equipped: inout [String: String], manifest: Manifest, valid: Set<String>) {
        let d = UserDefaults.standard
        var version = max(d.integer(forKey: versionKey), 1)   // 沒存過是 0，當作第 1 版
        guard version < currentVersion else { return }
        if version == 1 {
            // 第 2 版：兔耳、兔尾巴、耳環變成可以穿脫的物件。舊存檔（和第一次開啟）穿上角色原本的樣子；
            // 之後玩家脫掉就不會再被穿回去，因為版本已經是 2 了。
            for (slot, id) in manifest.defaultItems ?? [:] where equipped[slot] == nil && valid.contains(id) {
                equipped[slot] = id
            }
            version = 2
        }
        d.set(equipped, forKey: defaultsKey)
        d.set(version, forKey: versionKey)
    }

    func setHair(_ id: String) { setLook(Look(hair: id, clothes: look.clothes)) }
    func setClothes(_ id: String) { setLook(Look(hair: look.hair, clothes: id)) }

    private func setLook(_ new: Look) {
        look = new
        UserDefaults.standard.set(["hair": new.hair, "clothes": new.clothes], forKey: Self.lookKey)
        onChange?()
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
        window?.bringToFront()
    }
}

struct WardrobeView: View {
    @ObservedObject var wardrobe: Wardrobe
    @ObservedObject var stats: PetStats

    private var sprites: SpriteLibrary { wardrobe.sprites }

    var body: some View {
        VStack(spacing: 16) {
            // 大預覽：目前的穿搭
            PetPreview(sprites: sprites, outfits: wardrobe.equipped, look: wardrobe.look)
                .frame(width: 140, height: 140)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 外觀：髮型、衣服（純外觀，不加戰鬥力）
                    if let looks = sprites.manifest.looks {
                        Text("外觀（不影響戰鬥力）").font(.caption).foregroundStyle(.secondary)
                        lookRow("髮型", looks.hair, selected: wardrobe.look.hair) { id in
                            var l = wardrobe.look; l.hair = id; return l
                        } choose: { wardrobe.setHair($0) }
                        lookRow("衣服", looks.clothes, selected: wardrobe.look.clothes) { id in
                            var l = wardrobe.look; l.clothes = id; return l
                        } choose: { wardrobe.setClothes($0) }
                        // 耳朵、尾巴、耳飾：原本屬於某個角色的特徵，誰都能戴
                        ForEach(sprites.manifest.bodySlots ?? []) { slot in
                            slotRow(slot)
                        }
                        Divider()
                        Text("配件").font(.caption).foregroundStyle(.secondary)
                    }
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

    private func lookRow(_ title: String, _ options: [Manifest.LookOption], selected: String,
                         preview: @escaping (String) -> Look, choose: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            optionGrid {
                ForEach(options) { option in
                    Button { choose(option.id) } label: {
                        card(name: option.name, selected: option.id == selected) {
                            PetPreview(sprites: sprites, outfits: wardrobe.equipped, look: preview(option.id))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // 選項排成會自動換行的格子。不用橫向 ScrollView：它包在直向 ScrollView 裡時，
    // 游標停在某一排上用觸控板上下滑，滑動常被那一排吃掉，整個視窗就滑不動。
    private func optionGrid(@ViewBuilder content: () -> some View) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 10, alignment: .top)],
                  alignment: .leading, spacing: 10, content: content)
    }

    // 一張選項卡：縮圖 + 名字，選中時有框。
    private func card(name: String, selected: Bool, @ViewBuilder preview: () -> some View) -> some View {
        VStack(spacing: 4) {
            preview().frame(width: 64, height: 64)
            // 長名字換行（最多兩行），字不縮小；兩行固定高度讓卡片對齊，游標停上去看全名。
            Text(name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 30, alignment: .top)
        }
        .frame(width: 68)
        .help(name)
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

    private func slotRow(_ slot: Manifest.Slot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(slot.name).font(.headline)
            optionGrid {
                option(name: "無", outfitID: nil, slot: slot.id)
                ForEach(wardrobe.available(in: slot.id)) { outfit in
                    let name = sprites.displayName(outfit)
                    option(name: outfit.power.map { $0 > 0 ? "\(name) +\($0)" : name } ?? name,
                           outfitID: outfit.id, slot: slot.id)
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
            card(name: name, selected: selected) {
                PetPreview(sprites: sprites, outfits: preview, look: wardrobe.look)
            }
        }
        .buttonStyle(.plain)
    }
}

// 把本體和服裝疊起來的靜態預覽（使用 idle 第 0 格）。
struct PetPreview: View {
    let sprites: SpriteLibrary
    let outfits: [String: String]
    let look: Look

    // 由下往上：身後的服裝（翅膀）→ 本體各層 → 其他服裝。
    private var images: [NSImage] {
        let worn = sprites.manifest.slots.compactMap { outfits[$0.id] }
        let behind = worn.filter { sprites.isBehind($0, .idle, 0) }
        let front = worn.filter { !sprites.isBehind($0, .idle, 0) }
        return behind.compactMap { sprites.outfitFrame($0, .idle, 0) }
            + sprites.bodyLayers(look, items: outfits, .idle, 0).compactMap { $0 }
            + front.compactMap { sprites.outfitFrame($0, .idle, 0) }
    }

    var body: some View {
        ZStack {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image).resizable().scaledToFit()
            }
        }
    }
}
