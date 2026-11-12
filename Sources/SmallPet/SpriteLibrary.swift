// SpriteLibrary.swift —— 讀取目前角色的 manifest.json 與每一格圖片。
//
// 資料夾結構（<角色> 見 Character.swift）：
//   Resources/characters/<角色>/manifest.json            動作格數 / 速度、服裝清單
//   Resources/characters/<角色>/body/<動作>_<格>.png       寵物本體
//   Resources/characters/<角色>/outfits/<服裝id>/<動作>_<格>.png   服裝疊圖（與本體同尺寸、同格數）
//   Resources/props/<名字>.png                           家具等道具（所有角色共用）
//
// 圖片可以是 .png 或 .pdf（向量，放大不糊）。換外觀只要替換檔案，不用改程式。
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
    }

    let canvas: Canvas
    let actions: [String: ActionInfo]
    let slots: [Slot]       // 由下往上疊的順序
    let outfits: [Outfit]
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
}
