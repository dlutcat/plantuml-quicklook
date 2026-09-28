import AppKit
import WebKit
import UniformTypeIdentifiers

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var smoke: SmokeTests?
    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenu()
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--smoke-test"), args.count > index + 2 {
            smoke = SmokeTests(fixtures: URL(fileURLWithPath: args[index + 1]), output: URL(fileURLWithPath: args[index + 2]))
            smoke?.run(); return
        }
        let paths = args.dropFirst().filter { !$0.hasPrefix("-") }
        if !paths.isEmpty { paths.forEach { openFile(URL(fileURLWithPath: $0)) } }
        if windows.isEmpty { showWelcome() }
        NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        filenames.forEach { openFile(URL(fileURLWithPath: $0)) }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    private func makeMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "退出 PlantUML Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); bar.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件"); fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "打开 PlantUML…", action: #selector(chooseFile), keyEquivalent: "o").target = self
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem(); bar.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = bar
    }
    private func window(controller: NSViewController, title: String) {
        let win = NSWindow(contentViewController: controller)
        win.title = title
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 1000, height: 720))
        win.minSize = NSSize(width: 580, height: 360)
        win.isReleasedWhenClosed = false
        win.center(); win.makeKeyAndOrderFront(nil); windows.append(win)
    }
    private func openFile(_ url: URL) {
        let controller = RendererViewController()
        window(controller: controller, title: url.lastPathComponent)
        controller.preview(file: url)
    }
    @objc private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["puml", "plantuml", "pu", "wsd", "iuml"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach(openFile) }
    }
    private func showWelcome() {
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720))
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 22
        let title = NSTextField(labelWithString: "PlantUML Preview")
        title.font = .systemFont(ofSize: 30, weight: .semibold)
        let info = NSTextField(wrappingLabelWithString: "在 Finder 中选中 .puml 或 .plantuml 文件，按空格查看图表。\n\n首次使用：在系统设置 → 通用 → 登录项与扩展 → 快速查看中启用 PlantUML Preview。\n\n图表在本机渲染，无需 Java 或联网。支持缩放、多图切换与源码查看。")
        info.alignment = .center; info.font = .systemFont(ofSize: 15)
        let open = NSButton(title: "打开 PlantUML 文件…", target: self, action: #selector(chooseFile))
        let settings = NSButton(title: "打开扩展设置", target: self, action: #selector(openSettings))
        [title, info, open, settings].forEach(stack.addArrangedSubview)
        stack.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor), stack.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor), stack.widthAnchor.constraint(equalToConstant: 650)])
        window(controller: controller, title: "PlantUML Preview")
    }
    @objc private func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
    }
}

// Exercises the very same NSViewController/WebKit/origin used by the appex.
// Outputs SVGs, a screenshot, and JSON results for repeatable local verification.
final class SmokeTests {
    let fixtures: URL, output: URL
    var files: [URL] = [], results: [[String: Any]] = []
    var controller: RendererViewController?
    var window: NSWindow?
    init(fixtures: URL, output: URL) { self.fixtures = fixtures; self.output = output }
    func run() {
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            files = try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "puml" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !files.isEmpty else { throw PreviewFailure.message("No test fixtures") }
            next()
        } catch { fputs("Smoke test setup failed: \(error)\n", stderr); exit(1) }
    }
    func next() {
        guard !files.isEmpty else {
            let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            try! data.write(to: output.appendingPathComponent("results.json"))
            let failed = results.filter { !($0["passed"] as? Bool ?? false) }
            print("WebKit smoke tests: \(results.count - failed.count)/\(results.count) passed")
            exit(failed.isEmpty ? 0 : 1)
        }
        let file = files.removeFirst()
        let vc = RendererViewController(); controller = vc
        if window == nil {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        }
        window?.contentViewController = vc
        window?.makeKeyAndOrderFront(nil)
        vc.onResult = { [weak self, weak vc] body in
            guard let self, let vc else { return }
            vc.onResult = nil
            var record = body; record["file"] = file.lastPathComponent
            let expectedFailure = file.lastPathComponent.hasPrefix("error-")
            let rendered = body["ok"] as? Bool ?? false
            record["passed"] = expectedFailure ? !rendered : rendered && (body["width"] as? Double ?? 0) > 0
            print("\(record["passed"] as? Bool == true ? "PASS" : "FAIL") \(file.lastPathComponent): \(body["error"] ?? "")")
            self.results.append(record)
            guard let web = vc.webView else { self.next(); return }
            self.checkExports(web, file: file, result: body) {
                if file.lastPathComponent == "multiple.puml", rendered {
                    vc.onResult = { [weak self, weak vc] second in
                        guard let self else { return }
                        vc?.onResult = nil
                        var check = second
                        check["file"] = "multiple.puml:second-diagram"
                        check["passed"] = (second["ok"] as? Bool == true) && (second["text"] as? String ?? "").contains("第二张图的活动")
                        self.results.append(check)
                        print("\(check["passed"] as? Bool == true ? "PASS" : "FAIL") second diagram")
                        self.checkExports(web, file: file, result: second) { self.next() }
                    }
                    web.evaluateJavaScript("window.preview.select(1); void 0") { _, error in
                        if let error { vc.showFailure(error.localizedDescription) }
                    }
                    return
                }
                web.evaluateJavaScript("window.preview.svg()") { value, _ in
                    if let svg = value as? String { try? svg.write(to: self.output.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".svg"), atomically: true, encoding: .utf8) }
                    if file.lastPathComponent == "sequence.puml" {
                        web.takeSnapshot(with: nil) { image, _ in
                            if let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                                try? png.write(to: self.output.appendingPathComponent("preview.png"))
                            }
                            // Assert that network is blocked from this actual page,
                            // despite WebKit requiring a client entitlement to boot.
                            let probe = """
                            const blocked = new Promise(resolve => {
                              document.addEventListener('securitypolicyviolation', e => resolve(e.effectiveDirective === 'connect-src'), {once: true});
                              setTimeout(() => resolve(false), 1000);
                            });
                            fetch('https://example.invalid/plantuml-offline-test').catch(() => {});
                            return await blocked;
                            """
                            web.callAsyncJavaScript(probe, arguments: [:], in: nil, in: .page) { result in
                                let blocked = (try? result.get()) as? Bool ?? false
                                self.results.append(["file": "network-policy", "passed": blocked])
                                print("\(blocked ? "PASS" : "FAIL") network policy")
                                self.next()
                            }
                        }
                    } else { self.next() }
                }
            }
        }
        vc.preview(file: file)
    }

    private func checkExports(_ web: WKWebView, file: URL, result: [String: Any], completion: @escaping () -> Void) {
        let rendered = result["ok"] as? Bool ?? false
        let script = """
        const button = document.getElementById('download');
        if (!rendered) {
          let rejected = false;
          try { await window.preview.prepareExport('png'); } catch { rejected = true; }
          return {passed: button.disabled && rejected};
        }
        const svg = await window.preview.prepareExport('svg');
        document.getElementById('actual').click();
        document.getElementById('source-toggle').click();
        const hiddenSVG = await window.preview.prepareExport('svg');
        const png = await window.preview.prepareExport('png');
        document.getElementById('source-toggle').click();
        document.getElementById('fit').click();
        let rejected = false;
        try { await window.preview.prepareExport('jpeg'); } catch { rejected = true; }
        const parsed = new DOMParser().parseFromString(svg.content, 'image/svg+xml');
        const selected = Number(document.getElementById('diagrams').value) || 0;
        const suffix = document.getElementById('diagrams').options.length > 1 ? '-' + (selected + 1) : '';
        const expectedName = document.title.replace(/\\.[^.]+$/, '') + suffix;
        return {
          passed: !button.disabled && rejected && svg.content === hiddenSVG.content &&
            !parsed.querySelector('parsererror') && parsed.documentElement.textContent === expectedText &&
            svg.filename === expectedName + '.svg' && png.filename === expectedName + '.png',
          svg, png
        };
        """
        web.callAsyncJavaScript(script, arguments: ["rendered": rendered, "expectedText": result["text"] as? String ?? ""], in: nil, in: .page) { response in
            var passed = false
            var detail = ""
            do {
                guard let check = try response.get() as? [String: Any] else { throw PreviewFailure.message("Missing export result") }
                passed = check["passed"] as? Bool ?? false
                if rendered {
                    for format in ["svg", "png"] {
                        guard let payload = check[format] as? [String: Any] else { throw PreviewFailure.message("Missing image payload") }
                        let image = try ImageExport(payload)
                        let destination = self.output.appendingPathComponent("export-" + image.filename)
                        try image.write(to: destination)
                        let saved = try Data(contentsOf: destination)
                        passed = passed && saved == image.data
                        if format == "png" {
                            let bitmap = NSBitmapImageRep(data: saved)
                            passed = passed && bitmap?.pixelsWide == Int((result["width"] as? Double ?? 0) * 2)
                                && bitmap?.pixelsHigh == Int((result["height"] as? Double ?? 0) * 2)
                        }
                    }
                }
            } catch { detail = error.localizedDescription; passed = false }
            self.results.append(["file": file.lastPathComponent + ":image-export", "passed": passed, "error": detail])
            print("\(passed ? "PASS" : "FAIL") \(file.lastPathComponent) image export \(detail)")
            completion()
        }
    }
}
