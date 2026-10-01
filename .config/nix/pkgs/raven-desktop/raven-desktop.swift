// Raven — native macOS desktop wrapper for the Raven CLI agent.
//
// Raven's front end is a local web page served by `raven web` (which leaves a
// resident gateway behind). This is a small AppKit + WKWebView shell that owns
// that process instead of a browser tab:
//
//   launch -> attach to a running gateway, or spawn `raven web` -> wait for the
//             server -> load the page in a WKWebView
//   quit   -> stop the child, and (if this app started it) `raven web --stop`
//
// The paths below are substituted at build time by pkgs/raven-desktop/default.nix:
//   @RAVEN_BIN@   absolute path to the raven executable in the nix store
//   @PORT@        Raven's default page port
//
// The agent home (where serve.json lives) is resolved at runtime instead, so
// the bundle is not tied to one machine's user: $RAVEN_HOME if set, else
// ~/.raven.

import AppKit
import Darwin
import WebKit

private let ravenBinPath = "@RAVEN_BIN@"
private let defaultPort = Int("@PORT@") ?? 18792

private let ravenHomePath: String = {
    if let env = ProcessInfo.processInfo.environment["RAVEN_HOME"], !env.isEmpty {
        return (env as NSString).expandingTildeInPath
    }
    return (NSHomeDirectory() as NSString).appendingPathComponent(".raven")
}()

private let startupTimeoutS: TimeInterval = 150.0
private let pollIntervalS: TimeInterval = 0.3
private let stopTimeoutS: TimeInterval = 25.0

private let minPageZoom: CGFloat = 0.5
private let maxPageZoom: CGFloat = 3.0
private let pageZoomStep: CGFloat = 0.1

// The page zoom is remembered across launches. UserDefaults keys are shared by
// bundle identifier, so namespace ours to keep it clear of anything else.
private let pageZoomDefaultsKey = "com.ggr.raven-desktop.pageZoom"

private func logPath() -> String {
    return (ravenHomePath as NSString).appendingPathComponent("raven-desktop.log")
}

private func clampPageZoom(_ value: CGFloat) -> CGFloat {
    return min(maxPageZoom, max(minPageZoom, value))
}

// The stored value is clamped on the way in as well as out: a corrupt or
// out-of-range entry must not put the web view in a zoom it cannot recover from.
private func savedPageZoom() -> CGFloat {
    guard let value = UserDefaults.standard.object(forKey: pageZoomDefaultsKey) as? Double else {
        return 1.0
    }
    return clampPageZoom(CGFloat(value))
}

private func savePageZoom(_ value: CGFloat) {
    UserDefaults.standard.set(Double(clampPageZoom(value)), forKey: pageZoomDefaultsKey)
}

private struct ServeAuth {
    let port: Int
    let pid: pid_t
    let token: String
    let cookie: String?
}

private func readServeState() -> ServeAuth? {
    let path = (ravenHomePath as NSString).appendingPathComponent("serve.json")
    guard let data = FileManager.default.contents(atPath: path),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let port = obj["port"] as? Int,
          let token = obj["token"] as? String
    else { return nil }
    let pid = (obj["pid"] as? Int) ?? 0
    return ServeAuth(port: port, pid: pid_t(pid), token: token, cookie: obj["cookie"] as? String)
}

private func pidAlive(_ pid: pid_t) -> Bool {
    if pid <= 0 { return false }
    return kill(pid, 0) == 0 || errno == EPERM
}

private func httpJSON(
    _ url: URL,
    method: String = "GET",
    headers: [String: String] = [:],
    body: Data? = nil,
    timeout: TimeInterval = 2.0
) -> (status: Int, json: [String: Any]?) {
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.timeoutInterval = timeout
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    if let body = body {
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    var out: (Int, [String: Any]?) = (0, nil)
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { data, resp, _ in
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        var json: [String: Any]?
        if let data = data {
            json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        out = (code, json)
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + timeout + 3.0)
    return out
}

private func serverIsUp(port: Int) -> Bool {
    guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
    let (status, json) = httpJSON(url, timeout: 1.0)
    return status == 200 && (json?["service"] as? String) == "raven-serve"
}

private func mintAuthURL(port: Int, token: String) -> URL? {
    guard let url = URL(string: "http://127.0.0.1:\(port)/auth/nonce") else { return nil }
    let (status, json) = httpJSON(url, method: "POST", headers: ["X-Raven-Token": token], timeout: 2.0)
    guard status == 200, let nonce = json?["nonce"] as? String, !nonce.isEmpty else { return nil }
    return URL(string: "http://127.0.0.1:\(port)/auth#\(nonce)")
}

// Raven names its session cookie for the port it was served on (cookies ignore
// port, so two gateways would otherwise share one jar entry). Planting it into
// the web view's own cookie store is belt-and-braces beside the one-time nonce
// URL: a WKWebView loaded straight at `http://127.0.0.1:<port>/` is already
// authenticated, with no dependency on URLSession and WebKit sharing a jar.
private func installSessionCookie(port: Int, value: String) {
    let props: [HTTPCookiePropertyKey: Any] = [
        .name: "raven_session_\(port)",
        .value: value,
        .domain: "127.0.0.1",
        .path: "/",
        .version: 0,
    ]
    guard let cookie = HTTPCookie(properties: props) else { return }
    HTTPCookieStorage.shared.setCookie(cookie)
    WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
}

private struct Ready {
    let cookie: String?
    let authURL: URL?
}

private func tail(_ path: String, lines: Int) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
    let all = text.split(separator: "\n", omittingEmptySubsequences: false)
    return all.suffix(lines).joined(separator: "\n")
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var overlay: NSView!
    private var statusLabel: NSTextField!
    private var errorLabel: NSTextField!
    private var retryButton: NSButton!
    private var spinner: NSProgressIndicator!

    // Written on the startup thread (bringUpServer) and read on the main thread
    // (stopServer / quit), so they live behind a lock rather than racing.
    private let stateLock = NSLock()
    private var _child: Process?
    private var _startedServer = false
    private var _childExitCode: Int32?

    private func setChild(_ p: Process?) {
        stateLock.lock(); _child = p; stateLock.unlock()
    }

    private func currentChild() -> Process? {
        stateLock.lock(); defer { stateLock.unlock() }; return _child
    }

    private func setStartedServer(_ v: Bool) {
        stateLock.lock(); _startedServer = v; stateLock.unlock()
    }

    private func didStartServer() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }; return _startedServer
    }

    private func setChildExitCode(_ c: Int32?) {
        stateLock.lock(); _childExitCode = c; stateLock.unlock()
    }

    private func currentChildExitCode() -> Int32? {
        stateLock.lock(); defer { stateLock.unlock() }; return _childExitCode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        buildWindow()
        start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopServer()
    }

    // MARK: - UI

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Raven",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide Raven",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Raven",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let reload = NSMenuItem(title: "Reload Page", action: #selector(reloadPage), keyEquivalent: "r")
        reload.target = self
        viewMenu.addItem(reload)
        viewMenu.addItem(.separator())
        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+")
        zoomInItem.target = self
        viewMenu.addItem(zoomInItem)
        // Cmd+= is the unshifted equivalent users actually press. AppKit will
        // not match it to "+", so bind it on a hidden item that still responds.
        let zoomInUnshifted = NSMenuItem(title: "Zoom In", action: #selector(zoomIn), keyEquivalent: "=")
        zoomInUnshifted.target = self
        zoomInUnshifted.keyEquivalentModifierMask = [.command]
        zoomInUnshifted.isHidden = true
        zoomInUnshifted.allowsKeyEquivalentWhenHidden = true
        viewMenu.addItem(zoomInUnshifted)
        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-")
        zoomOutItem.target = self
        viewMenu.addItem(zoomOutItem)
        let actualSizeItem = NSMenuItem(title: "Actual Size", action: #selector(resetZoom), keyEquivalent: "0")
        actualSizeItem.target = self
        viewMenu.addItem(actualSizeItem)
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Raven"
        window.minSize = NSSize(width: 640, height: 480)
        window.setFrameAutosaveName("RavenDesktopWindow")
        window.center()

        let content = window.contentView!

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: content.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isHidden = true
        webView.pageZoom = savedPageZoom()
        content.addSubview(webView)

        overlay = NSView(frame: content.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true

        statusLabel = NSTextField(labelWithString: "Starting Raven…")
        statusLabel.alignment = .center
        statusLabel.font = NSFont.systemFont(ofSize: 15)

        errorLabel = NSTextField(labelWithString: "")
        errorLabel.alignment = .center
        errorLabel.font = NSFont.systemFont(ofSize: 13)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.maximumNumberOfLines = 0
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.isHidden = true

        retryButton = NSButton(title: "Retry", target: self, action: #selector(retry))
        retryButton.bezelStyle = .rounded
        retryButton.isHidden = true

        for view in [spinner, statusLabel, errorLabel, retryButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(view)
        }
        content.addSubview(overlay)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -60),

            statusLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 40),
            statusLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -40),

            errorLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            errorLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 40),
            errorLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -40),

            retryButton.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 20),
        ])

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        spinner.startAnimation(nil)
    }

    @objc private func reloadPage() {
        if webView.isHidden {
            start()
        } else {
            webView.reload()
        }
    }

    @objc private func retry() {
        start()
    }

    // MARK: - Zoom

    @objc private func zoomIn() {
        setPageZoom(webView.pageZoom + pageZoomStep)
    }

    @objc private func zoomOut() {
        setPageZoom(webView.pageZoom - pageZoomStep)
    }

    @objc private func resetZoom() {
        setPageZoom(1.0)
    }

    private func setPageZoom(_ value: CGFloat) {
        let zoom = clampPageZoom(value)
        webView.pageZoom = zoom
        savePageZoom(zoom)
    }

    private func showError(_ message: String) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        statusLabel.isHidden = true
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        retryButton.isHidden = false
        webView.isHidden = true
        overlay.isHidden = false
    }

    // MARK: - Server lifecycle

    private func start() {
        overlay.isHidden = false
        spinner.isHidden = false
        spinner.startAnimation(nil)
        statusLabel.isHidden = false
        statusLabel.stringValue = "Starting Raven…"
        errorLabel.isHidden = true
        retryButton.isHidden = true
        webView.isHidden = true

        setChildExitCode(nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = self.bringUpServer()
            DispatchQueue.main.async {
                switch outcome {
                case .success(let ready): self.loadPage(ready)
                case .failure(let error): self.showError(error.message)
                }
            }
        }
    }

    private enum Outcome {
        case success(Ready)
        case failure(StartError)
    }

    private struct StartError: Error {
        let message: String
    }

    // Attach to a gateway that is already running, or start one. On success the
    // main thread installs the session cookie and loads the page.
    private func bringUpServer() -> Outcome {
        if let state = readServeState(), pidAlive(state.pid), serverIsUp(port: state.port) {
            setStartedServer(false)
            return .success(Ready(cookie: state.cookie, authURL: mintAuthURL(port: state.port, token: state.token)))
        }

        guard FileManager.default.isExecutableFile(atPath: ravenBinPath) else {
            return .failure(StartError(message: "The raven executable was not found at \(ravenBinPath)."))
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ravenBinPath)
        proc.arguments = ["web", "--port", String(defaultPort)]
        var env = ProcessInfo.processInfo.environment
        // `raven web` calls webbrowser.open() to show the page. Point it at
        // /usr/bin/true so it does not also pop a browser tab beside our window.
        env["BROWSER"] = "/usr/bin/true"
        proc.environment = env

        let handle = prepareLogHandle()
        proc.standardOutput = handle
        proc.standardError = handle
        proc.standardInput = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async { self?.setChildExitCode(p.terminationStatus) }
        }
        do {
            try proc.run()
        } catch {
            return .failure(StartError(message: "Could not start `raven web`: \(error.localizedDescription)"))
        }
        setChild(proc)
        setStartedServer(true)

        let deadline = Date().addingTimeInterval(startupTimeoutS)
        var exitedAt: Date?
        while Date() < deadline {
            if let state = readServeState(), pidAlive(state.pid), serverIsUp(port: state.port) {
                return .success(Ready(cookie: state.cookie, authURL: mintAuthURL(port: state.port, token: state.token)))
            }
            if let code = currentChildExitCode() {
                if code != 0 {
                    return .failure(StartError(message: failureMessage(
                        "`raven web` exited with status \(code) before the server came up."
                    )))
                }
                // `raven web` exits 0 once it has handed off to the resident
                // supervisor; keep waiting a little longer for the page.
                if exitedAt == nil { exitedAt = Date() }
                if let exitedAt = exitedAt, Date().timeIntervalSince(exitedAt) > 30 {
                    return .failure(StartError(message: failureMessage(
                        "`raven web` finished but the server is not answering."
                    )))
                }
            }
            Thread.sleep(forTimeInterval: pollIntervalS)
        }
        return .failure(StartError(message: failureMessage(
            "Raven's server did not come up within \(Int(startupTimeoutS))s."
        )))
    }

    private func prepareLogHandle() -> FileHandle {
        let path = logPath()
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            return handle
        }
        return FileHandle.nullDevice
    }

    private func failureMessage(_ lead: String) -> String {
        let tailText = tail(logPath(), lines: 12).trimmingCharacters(in: .whitespacesAndNewlines)
        if tailText.isEmpty {
            return "\(lead)\n\nCheck that Raven is installed and working, then Retry."
        }
        return "\(lead)\n\nRecent `raven web` output:\n\(tailText)"
    }

    private func loadPage(_ ready: Ready) {
        if let cookie = ready.cookie {
            let port = currentPort()
            if port > 0 { installSessionCookie(port: port, value: cookie) }
        }
        overlay.isHidden = true
        spinner.stopAnimation(nil)
        webView.isHidden = false
        let url = ready.authURL ?? URL(string: "http://127.0.0.1:\(currentPort())/")
        if let url = url {
            webView.load(URLRequest(url: url))
        }
    }

    private func currentPort() -> Int {
        if let state = readServeState(), state.port > 0 { return state.port }
        return defaultPort
    }

    private func stopServer() {
        if let proc = currentChild(), proc.isRunning {
            proc.terminate()
            let deadline = Date().addingTimeInterval(3)
            while proc.isRunning && Date() < deadline {
                usleep(50_000)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
        // Only tear down a server this app started. If we attached to one the
        // user already had running, leave it as we found it.
        guard didStartServer() else { return }
        let stop = Process()
        stop.executableURL = URL(fileURLWithPath: ravenBinPath)
        stop.arguments = ["web", "--stop"]
        stop.standardOutput = FileHandle.nullDevice
        stop.standardError = FileHandle.nullDevice
        do {
            try stop.run()
        } catch {
            return
        }
        let deadline = Date().addingTimeInterval(stopTimeoutS)
        while stop.isRunning && Date() < deadline {
            usleep(100_000)
        }
        if stop.isRunning {
            stop.terminate()
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        overlay.isHidden = true
        spinner.stopAnimation(nil)
        webView.isHidden = false
        webView.pageZoom = savedPageZoom()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError("Could not load the Raven page: \(error.localizedDescription)")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
