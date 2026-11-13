// PetAction.swift —— 寵物會做的所有動作。
//
// 每個動作的名字（rawValue）對應 manifest.json 的 actions 和 sheet.start，例如 walk → sprite sheet 裡 walk 的那幾格
import Foundation

enum PetAction: String, CaseIterable {
    case idle       // 發呆
    case walk       // 走路
    case run        // 跑步
    case jump       // 跳躍（圖片 4 格：0 蹲下、1 上升、2 下降、3 落地）
    case sit        // 坐下
    case sleep      // 睡覺
    case fall       // 在空中往下掉（被丟出去時）
    case dragged    // 被滑鼠抓著
    case dance      // 跳舞（原地，仿 GIF 的舞步）
    case parachute  // 從高處掉下來時打開降落傘，慢慢飄下去
    case parasol    // 只用來顯示：拿著雨傘時，降落傘改成撐傘飄下去（物理上還是 parachute）
    case eat        // 坐著啃胡蘿蔔（餵食時）
    case typing     // 坐在電腦桌前打電腦
    case swing      // 盪鞦韆
    case fly        // 開飛機

    // 選單上顯示的名字。
    var displayName: String {
        switch self {
        case .idle: "發呆"
        case .walk: "走路"
        case .run: "跑步"
        case .jump: "跳躍"
        case .sit: "坐下"
        case .sleep: "睡覺"
        case .fall: "掉落"
        case .dragged: "被抓住"
        case .dance: "跳舞"
        case .parachute: "降落傘"
        case .parasol: "撐傘"
        case .eat: "吃東西"
        case .typing: "打電腦"
        case .swing: "盪鞦韆"
        case .fly: "開飛機"
        }
    }

    // 可以從選單手動指定的動作（掉落、被抓住、降落傘是物理狀態；吃東西、打電腦、盪鞦韆要走到家具旁才做，都不給選）。
    static let selectable: [PetAction] = [.idle, .walk, .run, .jump, .sit, .sleep, .dance]

    // 自動模式下隨機挑選動作的權重，數字越大越常出現。偏安靜：多坐多發呆，少跑跳。
    var autoWeight: Int {
        switch self {
        case .idle: 28
        case .walk: 22
        case .sit: 22
        case .sleep: 12
        case .jump: 5
        case .run: 4
        case .dance: 4
        case .fall, .dragged, .parachute, .parasol, .eat, .typing, .swing, .fly: 0
        }
    }

    // 自動模式下，這個動作要持續多久（秒）才換下一個。
    var autoDuration: ClosedRange<Double> {
        switch self {
        case .idle: 4...10
        case .walk: 3...7
        case .run: 2...3
        case .sit: 10...25
        case .sleep: 25...60
        case .dance: 4...6      // 一輪 2 秒，大約跳 2～3 輪
        case .eat: 3...3
        case .typing: 20...45
        case .swing: 15...30
        case .fly: 20...35      // 在天上繞多久，之後才開始降落
        case .jump, .fall, .dragged, .parachute, .parasol: 0...0   // 由物理決定何時結束
        }
    }
}
