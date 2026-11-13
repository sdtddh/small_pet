// SpriteLibrary.swift —— 讀取目前角色的 manifest.json、共用的 items.json 與每一格圖片。
//
// 每一層的所有動作、所有格拼成一張 sprite sheet（<層>.png），manifest 的 sheet 記下怎麼切。
// 資料夾結構（<角色> 見 Character.swift）：
//   Resources/characters/<角色>/character.json           名字、臉、預設穿什麼
//   Resources/characters/<角色>/manifest.json            動作格數 / 速度、sheet 的切法
//   Resources/characters/<角色>/{face,features}.png      角色的臉、五官
//   Resources/characters/<角色>/outfits/<服裝id>.png      跟角色輪廓有關的服裝
//   Resources/shared/items.json                          部位、服裝、物件、髮型、衣服的清單（所有角色共用）
//   Resources/shared/{outfits,looks,items}/…             共用的圖層；角色資料夾裡找不到某一層時來這裡找
//   Resources/props/<名字>.png                           家具等道具（所有角色共用）
//
// 舊素材：清單直接寫在 manifest.json（沒有 items.json）、只有一張 body.png（沒有 looks）。
//
// manifest 沒有 sheet 的舊素材，還是讀一格一張的 <層>/<動作>_<格>.png（或 .pdf）。
import AppKit

struct Manifest {
    struct Canvas: Decodable {
        let width: Double
        let height: Double
    }
    struct ActionInfo: Decodable {
        let frames: Int
        let fps: Double
        let loop: Bool
    }
    struct Slot: Decodable, Identifiable {
        let id: String
        let name: String
    }
    struct Outfit: Decodable, Identifiable {
        let id: String
        let name: String
        let slot: String
        let power: Int?       // 戰鬥力加成（舊素材沒有這欄就當 0）
        let dungeon: Bool?    // true：要從地下城拿到才能穿
        let behind: Bool?     // true：畫在她身後（翅膀），正面時要疊在本體下面
        let behindActions: [String]?  // 這些動作時也疊在本體下面（撐傘飄下來時的傘柄）
        let origin: String?   // 原本屬於哪個角色（兔耳是阿米婭的），衣櫃顯示成「兔耳（阿米婭）」
        let colorFromHair: Bool?      // 用髮色畫：每種髮型各一張圖 items/<id>/<髮型id>.png
    }
    // 純外觀的髮型 / 衣服（不加戰鬥力）。預設穿哪個看 character.json，沒寫就是第一個。
    struct LookOption: Decodable, Identifiable {
        let id: String
        let name: String
        let origin: String?   // 原本屬於哪個角色，衣櫃顯示成「短髮（阿米婭）」
    }
    struct Looks: Decodable {
        let hair: [LookOption]
        let clothes: [LookOption]
    }

    var canvas: Canvas
    var actions: [String: ActionInfo]
    var slots: [Slot]       // 由下往上疊的順序
    var outfits: [Outfit]
    var looks: Looks?               // 舊素材（例如小貓）沒有外觀圖層
    var backFrames: [String: [Int]]?  // 背對畫面的格（動作名 → 第幾格）
    // sprite sheet 的切法：每列 columns 格、每格 cell 像素；動作的第 i 格是第 start[動作] + i 格（由左到右、由上到下）
    struct Sheet: Decodable {
        let columns: Int
        let cell: Int
        let start: [String: Int]
    }
    var sheet: Sheet?
    // 畫在本體圖層之間的部位（耳朵、尾巴、耳飾），物件一樣放在 outfits 裡
    var bodySlots: [Slot]?
    var defaultItems: [String: String]?     // 角色原本的樣子：部位 id → 物件 id
    var defaultLook: Look?                  // 角色原本的髮型 / 衣服
    var characterNames: [String: String]?   // 角色 id → 名字（顯示物件來源用）

    // 角色的 manifest.json。舊素材把服裝清單也寫在這裡；新素材的清單在 shared/items.json。
    private struct File: Decodable {
        let canvas: Canvas
        let actions: [String: ActionInfo]
        let backFrames: [String: [Int]]?
        let sheet: Sheet?
        let slots: [Slot]?
        let outfits: [Outfit]?
        let looks: Looks?
        let bodySlots: [Slot]?
        let defaultItems: [String: String]?
        let characterNames: [String: String]?
    }
    // shared/items.json
    private struct Catalog: Decodable {
        let slots: [Slot]
        let bodySlots: [Slot]?
        let outfits: [Outfit]
        let looks: Looks?
    }

    // 讀角色的 manifest.json，再補上 shared/items.json 的清單和 character.json 的預設穿著。
    static func load(character root: URL, shared: URL, info: CharacterInfo?) throws -> Manifest {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let catalog = try? JSONDecoder().decode(Catalog.self, from: Data(contentsOf: shared.appendingPathComponent("items.json")))
        var m = Manifest(canvas: file.canvas, actions: file.actions,
                         slots: catalog?.slots ?? file.slots ?? [], outfits: catalog?.outfits ?? file.outfits ?? [],
                         looks: catalog?.looks ?? file.looks, backFrames: file.backFrames, sheet: file.sheet,
                         bodySlots: catalog?.bodySlots ?? file.bodySlots, defaultItems: file.defaultItems,
                         defaultLook: nil, characterNames: file.characterNames)
        if let defaults = info?.defaults {
            let bodySlotIDs = Set((m.bodySlots ?? []).map(\.id))
            m.defaultItems = defaults.filter { bodySlotIDs.contains($0.key) }.compactMapValues { $0 }
            if let looks = m.looks {
                let hair = defaults["hair"].flatMap { $0 }.flatMap { id in looks.hair.first { $0.id == id } } ?? looks.hair.first
                let clothes = defaults["clothes"].flatMap { $0 }.flatMap { id in looks.clothes.first { $0.id == id } } ?? looks.clothes.first
                if let hair, let clothes { m.defaultLook = Look(hair: hair.id, clothes: clothes.id) }
            }
        }
        if m.characterNames == nil {
            m.characterNames = Dictionary(uniqueKeysWithValues: Character.all.map { ($0.id, $0.name) })
        }
        return m
    }
}

// 目前選的外觀：髮型 id + 衣服 id。
struct Look: Equatable {
    var hair: String
    var clothes: String
}

@MainActor
final class SpriteLibrary {

    let manifest: Manifest
    let root: URL           // 目前角色的資料夾（台詞檔 phrases.json 也放這裡）
    private let shared: URL // Resources 資料夾（共用的道具圖）

    // 讀過的圖片快取起來，key 是 "body/walk" 或 "outfits/cap/walk"。
    private var cache: [String: [NSImage]] = [:]

    init() {
        guard let shared = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            fatalError("找不到 Resources 資料夾，請先執行 swift Tools/generate-bunny.swift")
        }
        self.shared = shared
        root = shared.appendingPathComponent("characters/\(Character.current)")
        do {
            manifest = try Manifest.load(character: root, shared: shared.appendingPathComponent("shared"),
                                         info: Character.info(Character.current))
        } catch {
            fatalError("manifest.json 讀取失敗：\(error)")
        }
    }

    var canvasSize: NSSize {
        NSSize(width: manifest.canvas.width, height: manifest.canvas.height)
    }

    func info(_ action: PetAction) -> Manifest.ActionInfo {
        manifest.actions[action.rawValue] ?? Manifest.ActionInfo(frames: 1, fps: 1, loop: true)
    }

    // 寵物本體某個動作的第 frame 格。
    // 素材沒畫這個動作（例如小貓版沒有 dance）就用 idle 代替，不會整隻消失。
    func bodyFrame(_ action: PetAction, _ frame: Int) -> NSImage? {
        image(in: "body", action: action, frame: frame)
            ?? image(in: "body", action: .idle, frame: frame)
    }

    // 本體有幾層（PetView 依這個數字建圖層）。
    var bodyLayerCount: Int {
        manifest.looks == nil ? 1 : manifest.bodySlots == nil ? 4 : 10
    }

    // 本體的各層圖，由下往上（見 generate-bunny.swift 的 BodyPart）：
    // 垂在身後的頭髮、衣服和手腳、尾巴、耳朵、後腦頭髮、臉、前面的頭髮、耳環、五官、舉高的手。
    // items 是身上的物件（部位 id → 物件 id），只用到 bodySlots 的那幾個。
    // 素材沒有外觀圖層的話，就只有一張完整的 body 圖；舊版外觀素材是 behind / base / head / top 四層。
    func bodyLayers(_ look: Look, items: [String: String], _ action: PetAction, _ frame: Int) -> [NSImage?] {
        guard manifest.looks != nil else { return [bodyFrame(action, frame)] }
        guard manifest.bodySlots != nil else {
            return [
                lookFrame("looks/hair/\(look.hair)/behind", action, frame),
                lookFrame("looks/clothes/\(look.clothes)/base", action, frame),
                lookFrame("looks/hair/\(look.hair)/head", action, frame),
                lookFrame("looks/clothes/\(look.clothes)/top", action, frame),
            ]
        }
        func item(_ slot: String) -> NSImage? {
            items[slot].flatMap { itemFrame($0, look, action, frame) }
        }
        return [
            lookFrame("looks/hair/\(look.hair)/behind", action, frame),
            lookFrame("looks/clothes/\(look.clothes)/base", action, frame),
            item("tail"),
            item("ears"),
            lookFrame("looks/hair/\(look.hair)/back", action, frame),
            lookFrame("face", action, frame),
            lookFrame("looks/hair/\(look.hair)/front", action, frame),
            item("earrings"),
            lookFrame("features", action, frame),
            lookFrame("looks/clothes/\(look.clothes)/top", action, frame),
        ]
    }

    // 畫在本體圖層之間的物件（兔耳…）。用髮色畫的物件依目前髮型挑圖。
    func itemFrame(_ id: String, _ look: Look, _ action: PetAction, _ frame: Int) -> NSImage? {
        let colorFromHair = manifest.outfits.first { $0.id == id }?.colorFromHair == true
        return lookFrame(colorFromHair ? "items/\(id)/\(look.hair)" : "items/\(id)", action, frame)
    }

    // 衣櫃顯示的名字：原本屬於某個角色的物件 / 髮型 / 衣服加上「（角色名）」。
    func displayName(_ outfit: Manifest.Outfit) -> String { displayName(outfit.name, origin: outfit.origin) }
    func displayName(_ option: Manifest.LookOption) -> String { displayName(option.name, origin: option.origin) }

    private func displayName(_ name: String, origin: String?) -> String {
        guard let origin else { return name }
        return "\(name)（\(manifest.characterNames?[origin] ?? origin)）"
    }

    // 預設外觀（character.json 的 defaults，沒寫就是清單裡各自的第一個）。
    var defaultLook: Look {
        manifest.defaultLook
            ?? Look(hair: manifest.looks?.hair.first?.id ?? "", clothes: manifest.looks?.clothes.first?.id ?? "")
    }

    // 這一格是不是背對畫面。
    func isBackView(_ action: PetAction, _ frame: Int) -> Bool {
        manifest.backFrames?[action.rawValue]?.contains(frame) ?? false
    }

    // 這件服裝這一格要不要疊在本體下面（翅膀在正面時是在身後的；撐傘時傘柄在頭後面）。
    func isBehind(_ outfitID: String, _ action: PetAction, _ frame: Int) -> Bool {
        guard let outfit = manifest.outfits.first(where: { $0.id == outfitID }) else { return false }
        return (outfit.behind == true && !isBackView(action, frame))
            || outfit.behindActions?.contains(action.rawValue) == true
    }

    private func lookFrame(_ folder: String, _ action: PetAction, _ frame: Int) -> NSImage? {
        image(in: folder, action: action, frame: frame) ?? image(in: folder, action: .idle, frame: frame)
    }

    // 某件服裝某個動作的第 frame 格。
    // 如果這件服裝沒畫這個動作，就退而使用 idle 的圖，至少不會整件消失。
    func outfitFrame(_ outfitID: String, _ action: PetAction, _ frame: Int) -> NSImage? {
        image(in: "outfits/\(outfitID)", action: action, frame: frame)
            ?? image(in: "outfits/\(outfitID)", action: .idle, frame: frame)
    }

    // 道具圖（Resources/props/<名字>.png），例如降落傘的傘面。
    func prop(_ name: String) -> NSImage? {
        NSImage(contentsOf: shared.appendingPathComponent("props/\(name).png"))
    }

    func outfits(in slot: String) -> [Manifest.Outfit] {
        manifest.outfits.filter { $0.slot == slot }
    }

    // MARK: - 讀檔

    private func image(in folder: String, action: PetAction, frame: Int) -> NSImage? {
        let frames = loadFrames(folder: folder, action: action)
        guard !frames.isEmpty else { return nil }
        return frames[frame % frames.count]
    }

    private func loadFrames(folder: String, action: PetAction) -> [NSImage] {
        let key = "\(folder)/\(action.rawValue)"
        if let cached = cache[key] { return cached }

        if let sheet = manifest.sheet {
            let frames = sheetFrames(folder: folder, action: action, sheet: sheet)
            cache[key] = frames
            return frames
        }
        var frames: [NSImage] = []
        for i in 0..<info(action).frames {
            let base = root.appendingPathComponent("\(folder)/\(action.rawValue)_\(i)")
            let found = ["pdf", "png"].lazy
                .map { base.appendingPathExtension($0) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            guard let url = found, let image = NSImage(contentsOf: url) else { break }
            frames.append(image)
        }
        cache[key] = frames
        return frames
    }

    // 整張 sprite sheet，一層讀一次。nil 表示這一層沒有圖（存成 .some(nil)，不會一直重讀）。
    private var sheets: [String: CGImage?] = [:]

    private func sheetImage(_ folder: String) -> CGImage? {
        if let cached = sheets[folder] { return cached }
        // 先找角色自己的資料夾，沒有再找所有角色共用的 Resources/shared
        let image = [root, shared.appendingPathComponent("shared")].lazy
            .map { $0.appendingPathComponent("\(folder).png") }
            .compactMap { CGImageSourceCreateWithURL($0 as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } }
            .first
        sheets[folder] = .some(image)
        return image
    }

    // 從 sprite sheet 切出某個動作的每一格（切出來的圖跟整張共用記憶體）。
    private func sheetFrames(folder: String, action: PetAction, sheet: Manifest.Sheet) -> [NSImage] {
        guard let start = sheet.start[action.rawValue], let image = sheetImage(folder) else { return [] }
        let cell = sheet.cell, size = NSSize(width: cell, height: cell)
        return (0..<info(action).frames).compactMap { i in
            let k = start + i
            let rect = CGRect(x: (k % sheet.columns) * cell, y: (k / sheet.columns) * cell, width: cell, height: cell)
            return image.cropping(to: rect).map { NSImage(cgImage: $0, size: size) }
        }
    }
}
