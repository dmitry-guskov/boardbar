import SwiftUI
import WebKit

let vaultName = "Obsidian Vault"
let defaultBoardPath = NSHomeDirectory() + "/Documents/Obsidian Vault/07 Meta/board.json"

func boardPath() -> String {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--board"), i + 1 < args.count { return args[i + 1] }
    return UserDefaults.standard.string(forKey: "boardPath") ?? defaultBoardPath
}

final class Store: ObservableObject {
    @Published var board: [String: Any]?
    @Published var health: [String: Any] = ["state": "missing", "message": "No board snapshot yet."]
    @Published var topCount = 0
    let path = boardPath()
    private var lastMTime: Date?
    private var timer: Timer?
    private let iso = ISO8601DateFormatter()
    private lazy var cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BoardBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last-good.json")
    }()

    init() {
        if let data = try? Data(contentsOf: cacheURL), let obj = validate(data) { board = obj }
        reload(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.reload(force: false) }
    }

    var healthState: String { health["state"] as? String ?? "missing" }

    func validate(_ data: Data) -> [String: Any]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["version"] as? Int) == 1,
              let gen = obj["generated_at"] as? String, parseDate(gen) != nil,
              obj["tasks"] is [[String: Any]] else { return nil }
        return obj
    }

    func parseDate(_ s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        return f.date(from: s)
    }

    func reload(force: Bool) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = attrs?[.modificationDate] as? Date
        if mtime == nil {
            health = ["state": "missing", "message": "board.json not found"]
        } else if force || mtime != lastMTime {
            lastMTime = mtime
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let obj = validate(data) {
                board = obj
                try? data.write(to: cacheURL, options: .atomic)
                health = ["state": "ok"]
            } else {
                health = ["state": "invalid", "message": "Latest board.json is invalid — keeping last good snapshot"]
            }
        }
        if healthState == "ok", let b = board { health = staleness(b) }
        topCount = (board?["top_ids"] as? [String])?.count ?? 0
    }

    func staleness(_ b: [String: Any]) -> [String: Any] {
        let now = Date()
        if b["fixture"] as? Bool == true { return ["state": "ok"] }
        if let n = b["next_refresh_at"] as? String, let d = parseDate(n) {
            if now > d.addingTimeInterval(3 * 3600) { return ["state": "stale", "message": "Expected refresh did not arrive"] }
            return ["state": "ok"]
        }
        if let g = b["generated_at"] as? String, let d = parseDate(g), now.timeIntervalSince(d) > 36 * 3600 {
            return ["state": "stale", "message": "Snapshot is older than 36h"]
        }
        return ["state": "ok"]
    }

    var payloadJSON: String {
        var p: [String: Any] = ["health": health]
        if let b = board { p["board"] = b }
        let data = (try? JSONSerialization.data(withJSONObject: p)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    var icon: String {
        switch healthState {
        case "ok": return "checklist"
        case "stale": return "clock.badge.exclamationmark"
        default: return "exclamationmark.triangle"
        }
    }
}

struct WebBoard: NSViewRepresentable {
    @ObservedObject var store: Store

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "app")
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.web = web
        if let url = Bundle.main.url(forResource: "board", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) { context.coordinator.push() }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let store: Store
        weak var web: WKWebView?
        var ready = false
        init(store: Store) { self.store = store }

        func push() {
            guard ready, let web else { return }
            web.evaluateJavaScript("render(\(store.payloadJSON))")
        }

        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if let note = body["open"] as? String {
                var comps = URLComponents(string: "obsidian://open")!
                comps.queryItems = [URLQueryItem(name: "vault", value: vaultName), URLQueryItem(name: "file", value: note)]
                if let url = comps.url { NSWorkspace.shared.open(url) }
            }
            switch body["act"] as? String {
            case "ready": ready = true; push()
            case "reload": store.reload(force: true); push()
            case "openfile": NSWorkspace.shared.open(URL(fileURLWithPath: store.path))
            case "quit": NSApp.terminate(nil)
            default: break
            }
        }
    }
}

@main
struct BoardBarApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            WebBoard(store: store)
                .frame(width: 440, height: 620)
                .onAppear { store.reload(force: false) }
        } label: {
            Image(systemName: store.icon)
            if store.topCount > 0 && store.healthState == "ok" { Text("\(store.topCount)") }
        }
        .menuBarExtraStyle(.window)
    }
}
