// SpriteLibrary.swift —— 讀取目前角色的 manifest.json 與每一格圖片。
//
// 每一層的所有動作、所有格拼成一張 sprite sheet（<層>.png），manifest 的 sheet 記下怎麼切。
// 資料夾結構（<角色> 見 Character.swift）：
//   Resources/characters/<角色>/manifest.json            動作格數 / 速度、服裝清單、sheet 的切法
//   Resources/characters/<角色>/body.png                  寵物本體（只有沒有 looks 的舊素材才用）
//   Resources/characters/<角色>/outfits/<服裝id>.png      服裝疊圖（與本體同尺寸、同格數）
//   Resources/characters/<角色>/looks/hair/<髮型id>/{behind,head}.png  外觀：髮型（有的話會取代 body）
//   Resources/characters/<角色>/looks/clothes/<衣服id>/{base,top}.png  外觀：衣服
//   Resources/shared/{outfits,looks}/…                   跟角色無關的圖層，所有角色共用一份；
//                                                         角色資料夾裡找不到某一層時才來這裡找
//   Resources/props/<名字>.png                           家具等道具（所有角色共用）
//
// manifest 沒有 sheet 的舊素材，還是讀一格一張的 <層>/<動作>_<格>.png（或 .pdf）。
import AppKit

struct Manifest: Decodable {
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
    // 純外觀的髮型 / 衣服（不加戰鬥力）。第一個是預設。
    struct LookOption: Decodable, Identifiable {
        let id: String
        let name: String
    }
    struct Looks: Decodable {
        let hair: [LookOption]
        let clothes: [LookOption]
    }

    let canvas: Canvas
    let actions: [String: ActionInfo]
    let slots: [Slot]       // 由下往上疊的順序
    let outfits: [Outfit]
    let looks: Looks?               // 舊素材（例如小貓）沒有外觀圖層
    let backFrames: [String: [Int]]?  // 背對畫面的格（動作名 → 第幾格）
    // sprite sheet 的切法：每列 columns 格、每格 cell 像素；動作的第 i 格是第 start[動作] + i 格（由左到右、由上到下）
    struct Sheet: Decodable {
        let columns: Int
        let cell: Int
        let start: [String: Int]
    }
    let sheet: Sheet?
    // 畫在本體圖層之間的部位（耳朵、尾巴、耳飾），物件一樣放在 outfits 裡
    let bodySlots: [Slot]?
    let defaultItems: [String: String]?     // 角色原本的樣子：部位 id → 物件 id
    let characterNames: [String: String]?   // 角色 id → 名字（顯示物件來源用）
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
            let data = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
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

    // 衣櫃顯示的名字：原本屬於某個角色的物件加上「（角色名）」。
    func displayName(_ outfit: Manifest.Outfit) -> String {
        guard let origin = outfit.origin else { return outfit.name }
        let owner = manifest.characterNames?[origin] ?? Character.all.first { $0.id == origin }?.name ?? origin
        return "\(outfit.name)（\(owner)）"
    }

    // 預設外觀（manifest 裡各自的第一個）。
    var defaultLook: Look {
        Look(hair: manifest.looks?.hair.first?.id ?? "", clothes: manifest.looks?.clothes.first?.id ?? "")
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
