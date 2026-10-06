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
// How long to wait for a stale gateway to go down after `raven web --stop`
// before starting a fresh one anyway.
private let staleRestartTimeoutS: TimeInterval = 10.0

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

// The web UI is a prebuilt bundle served read-only from the nix store and has
// no custom-CSS hook, so desktop-only style fixes are injected by the shell
// instead. Both exist because the window uses .fullSizeContentView with a
// hidden title bar, so the page runs to the very top of the window:
//
//   1. The macOS traffic lights float over the page's top-left corner, which is
//      the rail header. Nudge that row down 5px so its controls clear them.
//   2. Lock the outer window scroll. The shell stays exactly viewport-height
//      and clips; the rail and chat panes keep scrolling their own inner
//      containers (.scroll / .list / …), which already set
//      `overflow-y: auto; min-height: 0`.
//
// The selectors are plain class/element selectors in the bundle, and this
// stylesheet is appended last in <head>, so equal specificity resolves to
// these rules by cascade order.
private let desktopTweaksCSS = """
.rail { padding-top: 5px; }                 /* 1. clear the traffic lights */

html, body { overflow: hidden; height: 100%; }   /* 2. lock the outer scroll */
.app { height: 100dvh; overflow: hidden; }       /*    shell clips, panes scroll */
"""

// Wrapped in a WKUserScript at document end (main frame only) so document.head
// exists and any subframe is left alone. Appends a <style> element — not
// document.write, which would clobber the parsed document.
private func desktopTweaksUserScript() -> WKUserScript {
    let source = """
    (function () {
      var style = document.createElement('style');
      style.setAttribute('data-raven-desktop', 'tweaks');
      style.textContent = `\(desktopTweaksCSS)`;
      document.head.appendChild(style);
    })();
    """
    return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
}

// WKScriptMessageHandler name the interaction script posts to. Shared by the
// injection and the native side so the two cannot drift apart.
private let windowInteractionHandlerName = "ravenDesktop"

// The title bar is gone (hidden, transparent, full-size content view), so
// AppKit's own double-click-to-zoom and title-bar drag no longer happen over
// the page. This script restores both on the top strip of the window:
//
//   - dblclick with clientY < 30 (non-interactive target) -> zoom: fill the
//     screen, or shrink to 75% of it (centered) when already filling
//   - mousedown in the same strip, then mousemove -> send per-move deltas so
//     the native side can move the window under the cursor
//
// The strip deliberately starts below the traffic lights, which sit above the
// web view natively, and it bails on anything interactive so the rail header
// toggle and pane-head buttons up there keep working as before.
//
// Surviving the page's own event code takes two rules together:
//
//   1. Injection is .atDocumentStart, so this IIFE runs before any page
//      script. `document` exists at that point and addEventListener works
//      there, so ours registers first — and at the same target + phase,
//      registration order is call order, so our capture listener is ahead of
//      every listener the page ever adds on `document`.
//   2. All four listeners use the CAPTURE phase (third argument `true`), so
//      they run on the way down, before any target handler can
//      stopPropagation(). A bubble-phase document listener never fires if
//      something up the tree stopped the event — which was the first bug —
//      and a capture listener registered *after* the page's can still be
//      killed by its stopImmediatePropagation() — which was this round's.
//      Rule 1 is what rules that out; rule 2 alone was not enough.
//
// Registration touches no DOM beyond addEventListener itself: no queries, no
// reads, nothing the page could not have built yet. The one element whose
// existence is uncertain at documentStart (document.documentElement) is bound
// lazily in bindLeave() when the first drag starts, never at registration.
private func desktopInteractionUserScript() -> WKUserScript {
    let source = """
    (function () {
      var TOP_STRIP = 30;
      var INTERACTIVE = 'button, a, input, textarea, select, [role="button"], [contenteditable], summary';

      function post(message) {
        try { window.webkit.messageHandlers.\(windowInteractionHandlerName).postMessage(message); } catch (e) {}
      }

      function isInteractive(event) {
        var target = event.target;
        return !!(target && target.closest && target.closest(INTERACTIVE));
      }

      function inTopStrip(event) {
        return event.clientY < TOP_STRIP;
      }

      document.addEventListener('dblclick', function (event) {
        if (!inTopStrip(event) || isInteractive(event)) return;
        post({ type: 'zoomWindow' });
      }, true);

      var dragging = false;
      var lastX = 0;
      var lastY = 0;
      var leaveBound = false;
      var pendingDx = 0;
      var pendingDy = 0;
      var flushScheduled = false;

      function flushDrag() {
        flushScheduled = false;
        var dx = pendingDx;
        var dy = pendingDy;
        pendingDx = 0;
        pendingDy = 0;
        if (dx !== 0 || dy !== 0) post({ type: 'windowDrag', dx: dx, dy: dy });
      }

      function endDrag() {
        dragging = false;
        flushDrag();
      }

      // document.documentElement can still be null at documentStart, so the
      // pointer-left-page listener is bound here instead of at registration,
      // when the document has long been built.
      function bindLeave() {
        if (leaveBound || !document.documentElement) return;
        leaveBound = true;
        document.documentElement.addEventListener('mouseleave', endDrag);
      }

      document.addEventListener('mousedown', function (event) {
        if (event.button !== 0 || !inTopStrip(event) || isInteractive(event)) return;
        event.preventDefault();
        bindLeave();
        dragging = true;
        lastX = event.clientX;
        lastY = event.clientY;
      }, true);

      document.addEventListener('mousemove', function (event) {
        if (!dragging) return;
        var dx = event.clientX - lastX;
        var dy = event.clientY - lastY;
        lastX = event.clientX;
        lastY = event.clientY;
        if (dx === 0 && dy === 0) return;
        pendingDx += dx;
        pendingDy += dy;
        if (!flushScheduled) {
          flushScheduled = true;
          requestAnimationFrame(flushDrag);
        }
      }, true);

      document.addEventListener('mouseup', endDrag, true);
      window.addEventListener('blur', endDrag);
    })();
    """
    return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
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

// The nix store directory of the raven build this app was compiled against,
// e.g. "/nix/store/…-raven-0.2.3" from "/nix/store/…-raven-0.2.3/bin/raven".
// nil when the path is not a nix store path (e.g. a source build).
private let ownRavenStorePath: String? = {
    let binDir = (ravenBinPath as NSString).deletingLastPathComponent
    let storeDir = (binDir as NSString).deletingLastPathComponent
    guard storeDir.hasPrefix("/nix/store/") else { return nil }
    return storeDir
}()

// Run a process, discarding stderr, and return its stdout. nil if it could not
// be launched or exited non-zero (`ps` exits 1 for a pid that is gone).
private func captureProcess(_ executable: String, _ arguments: [String]) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = arguments
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = FileHandle.nullDevice
    proc.standardInput = FileHandle.nullDevice
    do {
        try proc.run()
    } catch {
        return nil
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
}

// Find a NAME=VALUE entry among the whitespace-separated environment shown by
// `ps eww`. The value must not contain whitespace for this to match, which is
// true of PYTHONPATH.
private func environmentValue(_ name: String, in psOutput: String) -> String? {
    let prefix = name + "="
    for token in psOutput.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }) {
        if token.hasPrefix(prefix) {
            return String(token.dropFirst(prefix.count))
        }
    }
    return nil
}

// The nix store directory of the raven build a process is running, read from
// the raven store path in its PYTHONPATH. The gateway's *executable* is the
// python interpreter (identical across builds), so PYTHONPATH is the only
// build-specific signal. nil when it cannot be determined (ps fails, process
// gone, or no raven store path found) so callers can fall back to attaching.
private func ravenStorePath(of pid: pid_t) -> String? {
    guard pid > 0 else { return nil }
    // `-e` prints the process environment, `ww` disables command-line truncation.
    guard let output = captureProcess("/bin/ps", ["eww", "-p", String(pid)]) else {
        return nil
    }
    guard let pythonPath = environmentValue("PYTHONPATH", in: output) else { return nil }
    let pattern = "/nix/store/[a-z0-9]+-raven-[0-9][^:/\\s]*"
    guard let range = pythonPath.range(of: pattern, options: .regularExpression) else { return nil }
    return String(pythonPath[range])
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

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var overlay: NSView!
    private var statusLabel: NSTextField!
    private var errorLabel: NSTextField!
    private var retryButton: NSButton!
    private var spinner: NSProgressIndicator!

    private var pendingDragDX: CGFloat = 0
    private var pendingDragDY: CGFloat = 0
    private var dragApplyScheduled = false

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
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: windowInteractionHandlerName
        )
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
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Raven"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 480)
        window.setFrameAutosaveName("RavenDesktopWindow")
        window.center()

        let content = window.contentView!

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Desktop-only CSS fixes (see desktopTweaksCSS); the bundle has no hook
        // of its own for them.
        config.userContentController.addUserScript(desktopTweaksUserScript())
        config.userContentController.addUserScript(desktopInteractionUserScript())
        config.userContentController.add(self, name: windowInteractionHandlerName)
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

    // Settings is a modal inside the web UI, not a URL. The page already binds
    // Cmd+, itself, so replay that keydown and let its own handler open the
    // dialog; `key` is what the page matches on.
    @objc private func openSettings() {
        webView.evaluateJavaScript(
            "document.dispatchEvent(new KeyboardEvent('keydown', " +
            "{key: ',', code: 'Comma', keyCode: 188, which: 188, metaKey: true, bubbles: true, cancelable: true}));"
        )
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
            // The gateway is resident across restarts by design, so after a
            // rebuild the one already running may be from an older raven build.
            // Attaching would serve that stale code. Compare the build the
            // process was started from against ours; when ours is newer (they
            // differ) stop the old gateway and fall through to starting fresh.
            // If the running build can't be determined, attach as before.
            let runningStore = ravenStorePath(of: state.pid)
            let isStale = runningStore != nil && ownRavenStorePath != nil && runningStore != ownRavenStorePath
            if isStale {
                stopStaleGateway()
            } else {
                setStartedServer(false)
                return .success(Ready(cookie: state.cookie, authURL: mintAuthURL(port: state.port, token: state.token)))
            }
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

    // Stop the resident gateway/supervisor so a fresh `raven web` can start.
    // Bounded: if it does not go down, bringsUpServer's start-fresh path still
    // runs (and will fail to bind if something is truly stuck, surfacing the
    // problem to the user rather than hanging here).
    private func stopStaleGateway() {
        let stop = Process()
        stop.executableURL = URL(fileURLWithPath: ravenBinPath)
        stop.arguments = ["web", "--stop"]
        stop.standardOutput = FileHandle.nullDevice
        stop.standardError = FileHandle.nullDevice
        stop.standardInput = FileHandle.nullDevice
        do {
            try stop.run()
        } catch {
            return
        }
        let deadline = Date().addingTimeInterval(staleRestartTimeoutS)
        while Date() < deadline {
            // serve.json gone, or its pid dead, means the gateway is down.
            if let state = readServeState(), pidAlive(state.pid) {
                Thread.sleep(forTimeInterval: pollIntervalS)
                continue
            }
            break
        }
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

    // MARK: - WKScriptMessageHandler

    // Native half of desktopInteractionUserScript: double-click in the top
    // strip zooms the window (fill / shrink to 75%), dragging it moves the
    // window.
    //
    // Units: the script posts CSS pixels. WKWebView reports them in the same
    // coordinate space AppKit measures windows in — points, not device pixels
    // — so no backingScaleFactor is involved on a Retina display. What does
    // scale them is the page zoom: webView.pageZoom magnifies rendering, so at
    // 2.0 one CSS pixel covers two points of window and the delta must be
    // multiplied to keep the window glued to the cursor.
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "zoomWindow":
            // Double-click toggles fill <-> shrink-to-75%, and the current
            // state is read off the frame itself (size vs the screen's
            // visibleFrame) rather than a stored flag, so a manual resize in
            // between cannot leave a stale "am I maximized" flag behind — the
            // next double-click just fills again.
            //
            // Never .fullScreen: this only sets a plain frame, so the result
            // stays a normal titled window.
            guard !window.styleMask.contains(.fullScreen) else { return }
            guard let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let current = window.frame.size
            let filling = abs(current.width - visible.width) <= 2
                && abs(current.height - visible.height) <= 2
            if filling {
                // 75% of the screen, centered in it.
                let size = NSSize(width: visible.width * 0.75, height: visible.height * 0.75)
                let origin = NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.midY - size.height / 2)
                window.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
            } else {
                window.setFrame(visible, display: true, animate: true)
            }
        case "windowDrag":
            // A full-screen window cannot be moved.
            guard !window.styleMask.contains(.fullScreen) else { return }
            guard let dx = body["dx"] as? Double, let dy = body["dy"] as? Double else { return }
            pendingDragDX += CGFloat(dx)
            pendingDragDY += CGFloat(dy)
            scheduleDragApply()
        default:
            break
        }
    }

    // Coalesce a burst of windowDrag messages into one window move per
    // main-runloop turn: N bridge messages arriving in a turn become one
    // setFrameOrigin instead of N window-server relayouts.
    private func scheduleDragApply() {
        guard !dragApplyScheduled else { return }
        dragApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.dragApplyScheduled = false
            let dx = self.pendingDragDX
            let dy = self.pendingDragDY
            self.pendingDragDX = 0
            self.pendingDragDY = 0
            guard dx != 0 || dy != 0 else { return }
            guard !self.window.styleMask.contains(.fullScreen) else { return }
            let scale = CGFloat(self.webView.pageZoom)
            var origin = self.window.frame.origin
            origin.x += dx * scale
            // JS's y axis runs top-down, AppKit's bottom-up: dragging the
            // cursor down must lower origin.y.
            origin.y -= dy * scale
            self.window.setFrameOrigin(self.clampedWindowOrigin(origin))
        }
    }

    // Keep the window inside the desktop while dragging — clamped against the
    // bounding box of every screen's visible frame, so the window can cross
    // freely between monitors but never leave the whole arrangement. Full
    // containment when it fits, otherwise at least a strip of it stays
    // reachable so it cannot be dragged out of reach.
    private func clampedWindowOrigin(_ origin: NSPoint) -> NSPoint {
        var desktop: NSRect?
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            desktop = desktop.map { $0.union(visible) } ?? visible
        }
        guard let box = desktop else { return origin }
        let size = window.frame.size

        let minX = size.width <= box.width ? box.minX : box.minX - size.width + 40
        let maxX = size.width <= box.width ? box.maxX - size.width : box.maxX - 40
        let minY = size.height <= box.height ? box.minY : box.minY - size.height + 40
        let maxY = size.height <= box.height ? box.maxY - size.height : box.maxY - 40

        var clamped = origin
        clamped.x = min(max(clamped.x, min(minX, maxX)), max(minX, maxX))
        clamped.y = min(max(clamped.y, min(minY, maxY)), max(minY, maxY))
        return clamped
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
