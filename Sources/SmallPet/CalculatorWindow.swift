// CalculatorWindow.swift —— 電腦桌的小工具：計算機。按住電腦桌往上拉就會打開。
//
// 上面是算式（可以直接用鍵盤打，Enter 算出結果），下面一行即時顯示答案或哪裡有問題；
// 再下面是按鍵和最近算過的紀錄（點一下把結果放回算式）。算式的規則見 MathExpression.swift。
import AppKit
import SwiftUI

@MainActor
final class CalculatorWindowController {

    private var window: NSWindow?
    private let model = CalculatorModel()

    // anchor：電腦桌視窗的位置，計算機開在它正上方。
    func show(above anchor: NSRect) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 470),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "計算機"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: CalculatorView(model: model))
            window = w
        }
        guard let window else { return }
        if !window.isVisible, let visible = NSScreen.main?.visibleFrame {
            let size = window.frame.size
            let x = min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width)
            let y = min(anchor.maxY + 8, visible.maxY - size.height)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        window.bringToFront()
        model.focusRequest += 1
    }
}

@MainActor
final class CalculatorModel: ObservableObject {
    @Published var text = ""
    @Published var history: [Entry] {
        didSet {
            UserDefaults.standard.set(history.map { [$0.expression, $0.result] }, forKey: Self.historyKey)
        }
    }
    @Published var focusRequest = 0

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let expression: String
        let result: String
    }

    private static let historyKey = "calculator.history"
    private static let historyLimit = 20

    init() {
        let saved = UserDefaults.standard.array(forKey: Self.historyKey) as? [[String]] ?? []
        history = saved.compactMap { $0.count == 2 ? Entry(expression: $0[0], result: $0[1]) : nil }
    }

    // 打字途中的預覽：算得出來就顯示答案；還沒打完不吵（顯示空白）；真的有錯才說哪裡錯。
    var preview: (text: String, isError: Bool) {
        do {
            return ("= " + MathExpression.format(try MathExpression.evaluate(text)), false)
        } catch let e as ExpressionError {
            return e == .incomplete || e == .empty ? ("", false) : (e.description, true)
        } catch {
            return ("", false)
        }
    }

    // 按 = 或 Enter：算出來就記進紀錄，算式換成答案，可以接著算。
    func evaluate() {
        guard let value = try? MathExpression.evaluate(text) else { return }
        let result = MathExpression.format(value)
        if result != text {
            history.insert(Entry(expression: text, result: result), at: 0)
            if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        }
        text = result
    }

    func insert(_ s: String) { text += s }

    func backspace() {
        // 一次刪掉整個函數名稱（「log(」、「ln(」、「√(」），不然要按好幾下
        for name in ["log(", "ln(", "√("] where text.hasSuffix(name) {
            text.removeLast(name.count)
            return
        }
        if !text.isEmpty { text.removeLast() }
    }

    func clear() { text = "" }
}

struct CalculatorView: View {
    @ObservedObject var model: CalculatorModel
    @FocusState private var focused: Bool

    // 按鍵：標籤、按下去插入的文字（nil = 特殊功能）、種類
    private enum Kind { case digit, op, fn, action, equals }
    private struct Key: Identifiable {
        let label: String
        let insert: String?
        let kind: Kind
        var id: String { label }
    }

    private let rows: [[Key]] = [
        [Key(label: "C", insert: nil, kind: .action), Key(label: "⌫", insert: nil, kind: .action),
         Key(label: "(", insert: "(", kind: .op), Key(label: ")", insert: ")", kind: .op), Key(label: "÷", insert: "÷", kind: .op)],
        [Key(label: "log", insert: "log(", kind: .fn), Key(label: "7", insert: "7", kind: .digit),
         Key(label: "8", insert: "8", kind: .digit), Key(label: "9", insert: "9", kind: .digit), Key(label: "×", insert: "×", kind: .op)],
        [Key(label: "ln", insert: "ln(", kind: .fn), Key(label: "4", insert: "4", kind: .digit),
         Key(label: "5", insert: "5", kind: .digit), Key(label: "6", insert: "6", kind: .digit), Key(label: "−", insert: "−", kind: .op)],
        [Key(label: "√", insert: "√(", kind: .fn), Key(label: "1", insert: "1", kind: .digit),
         Key(label: "2", insert: "2", kind: .digit), Key(label: "3", insert: "3", kind: .digit), Key(label: "+", insert: "+", kind: .op)],
        [Key(label: "xʸ", insert: "^", kind: .fn), Key(label: "π", insert: "π", kind: .fn),
         Key(label: "0", insert: "0", kind: .digit), Key(label: ".", insert: ".", kind: .digit), Key(label: "=", insert: nil, kind: .equals)],
    ]

    var body: some View {
        VStack(spacing: 10) {
            display
            keypad
            historyList
        }
        .padding(12)
        .frame(width: 300, height: 470)
        .onAppear { focused = true }
        .onChange(of: model.focusRequest) { _ in focused = true }
    }

    private var display: some View {
        let preview = model.preview
        return VStack(alignment: .trailing, spacing: 4) {
            TextField("輸入算式，例如 2(3+4)^2 ÷ log 100", text: $model.text)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .onSubmit { model.evaluate() }
            Text(preview.text.isEmpty ? " " : preview.text)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(preview.isError ? Color.orange : Color.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.1)))
    }

    private var keypad: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(rows[r]) { key in
                        Button { press(key) } label: {
                            Text(key.label)
                                .font(.system(size: key.kind == .fn ? 15 : 18, weight: .medium, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(key.kind == .equals ? Color.white : Color.primary)
                                .background(RoundedRectangle(cornerRadius: 8).fill(color(key.kind)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func color(_ kind: Kind) -> Color {
        switch kind {
        case .digit: Color.gray.opacity(0.14)
        case .op: Color.accentColor.opacity(0.16)
        case .fn: Color.purple.opacity(0.14)
        case .action: Color.orange.opacity(0.18)
        case .equals: Color.accentColor
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("紀錄").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !model.history.isEmpty {
                    Button("清除") { model.history.removeAll() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(model.history) { entry in
                        // 點一下：把結果接在算式後面（算式是空的就直接放進去）
                        Button { model.insert(entry.result) } label: {
                            HStack {
                                Text(entry.expression).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                                Spacer(minLength: 8)
                                Text("= \(entry.result)").lineLimit(1)
                            }
                            .font(.system(size: 13, design: .rounded))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("點一下把 \(entry.result) 放進算式")
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func press(_ key: Key) {
        switch key.label {
        case "C": model.clear()
        case "⌫": model.backspace()
        case "=": model.evaluate()
        default: model.insert(key.insert ?? "")
        }
        focused = true
    }
}
