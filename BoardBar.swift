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
    static let shared = Store()
    @Published var board: [String: Any]?
    private var boardRaw: String?
    @Published var previous: [String: Any]?
    @Published var health: [String: Any] = ["state": "missing", "message": "No board snapshot yet."]
    @Published var topCount = 0
    let path = boardPath()
    private var lastMTime: Date?
    private var timer: Timer?
    private let iso = ISO8601DateFormatter()
    private lazy var cacheDir: URL = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BoardBar")
        let key = String(path.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }, radix: 16)
        let dir = root.appendingPathComponent(key)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = root.appendingPathComponent("last-good.json")
        if path == defaultBoardPath, FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: dir.appendingPathComponent("last-good.json"))
            try? FileManager.default.moveItem(at: root.appendingPathComponent("previous.json"), to: dir.appendingPathComponent("previous.json"))
        }
        return dir
    }()
    private var cacheURL: URL { cacheDir.appendingPathComponent("last-good.json") }
    private var previousURL: URL { cacheDir.appendingPathComponent("previous.json") }

    init() {
        if let data = try? Data(contentsOf: cacheURL), let obj = validate(data) { board = obj; boardRaw = String(data: data, encoding: .utf8) }
        if let data = try? Data(contentsOf: previousURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { previous = obj }
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

    func summary(_ b: [String: Any]) -> [String: Any] {
        let keep = ["id", "title", "state", "due", "event_at", "area"]
        let tasks = (b["tasks"] as? [[String: Any]] ?? []).map { t in t.filter { keep.contains($0.key) } }
        return ["generated_at": b["generated_at"] ?? "", "tasks": tasks]
    }

    func reload(force: Bool) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = attrs?[.modificationDate] as? Date
        if mtime == nil {
            health = ["state": "missing", "message": "board.json not found"]
        } else if force || mtime != lastMTime {
            lastMTime = mtime
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let obj = validate(data) {
                if let cur = board, (cur["generated_at"] as? String) != (obj["generated_at"] as? String) {
                    let prev = summary(cur)
                    previous = prev
                    if let d = try? JSONSerialization.data(withJSONObject: prev) { try? d.write(to: previousURL, options: .atomic) }
                }
                board = obj
                boardRaw = String(data: data, encoding: .utf8)
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

    // The board is passed as its original text: re-serializing would reorder keys, and area order matters.
    var payloadJSON: String {
        func json(_ o: Any?) -> String {
            guard let o, let d = try? JSONSerialization.data(withJSONObject: o) else { return "null" }
            return String(data: d, encoding: .utf8) ?? "null"
        }
        return "{\"health\":\(json(health)),\"board\":\(boardRaw ?? "null"),\"previous\":\(json(previous))}"
    }

    var icon: String {
        switch healthState {
        case "ok": return "checklist"
        case "stale": return "clock.badge.exclamationmark"
        default: return "exclamationmark.triangle"
        }
    }
}

final class ExpandedWindow: NSObject, NSWindowDelegate {
    static let shared = ExpandedWindow()
    private var window: NSWindow?

    func show(store: Store) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Board"
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.fullScreenPrimary]
            w.contentViewController = NSHostingController(rootView:
                WebBoard(store: store, mode: "full")
                    .frame(minWidth: 900, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity))
            w.setContentSize(NSSize(width: 1320, height: 860))
            w.center()
            w.setFrameAutosaveName("BoardBarExpanded")
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func toggleFullScreen() { window?.toggleFullScreen(nil) }

    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
}

struct WebBoard: NSViewRepresentable {
    @ObservedObject var store: Store
    var mode = "popover"

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "app")
        config.userContentController.addUserScript(WKUserScript(
            source: "window.BOARD_MODE='\(mode)';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
            if let link = body["url"] as? String, let url = URL(string: link), ["http", "https"].contains(url.scheme ?? "") {
                NSWorkspace.shared.open(url)
            }
            switch body["act"] as? String {
            case "ready":
                ready = true; push()
                if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count, web?.window != nil {
                    let out = CommandLine.arguments[i + 1]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.web?.takeSnapshot(with: nil) { image, _ in
                            if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                               let png = rep.representation(using: .png, properties: [:]) {
                                try? png.write(to: URL(fileURLWithPath: out))
                            }
                        }
                    }
                }
            case "reload": store.reload(force: true); push()
            case "openfile": NSWorkspace.shared.open(URL(fileURLWithPath: store.path))
            case "expand": ExpandedWindow.shared.show(store: store)
            case "fullscreen": ExpandedWindow.shared.toggleFullScreen()
            case "quit": NSApp.terminate(nil)
            default: break
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--expanded") { ExpandedWindow.shared.show(store: Store.shared) }
    }
}

@main
struct BoardBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = Store.shared

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
