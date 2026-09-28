import AppKit
import WebKit
import UniformTypeIdentifiers

enum PreviewFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum SourceReader {
    static let maximumBytes = 1_048_576
    static func read(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw PreviewFailure.message("文件超过 1 MB，请拆分后预览。") }
        // UTF-16 is accepted only with a BOM, to avoid interpreting arbitrary binary data as text.
        let encoding: String.Encoding = data.starts(with: [0xff, 0xfe]) ? .utf16LittleEndian :
            data.starts(with: [0xfe, 0xff]) ? .utf16BigEndian : .utf8
        guard let text = String(data: data, encoding: encoding), !text.contains("\0") else {
            throw PreviewFailure.message("无法读取文件编码。请将 PlantUML 文件保存为 UTF-8 或带 BOM 的 UTF-16。")
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
    }
}

// Both the save panel and smoke tests use the same payload validation and writer.
struct ImageExport {
    let filename: String
    let contentType: UTType
    let data: Data

    init(_ payload: [String: Any]) throws {
        guard let format = payload["format"] as? String,
              let name = payload["filename"] as? String,
              let content = payload["content"] as? String,
              !content.isEmpty, content.utf8.count <= 64 * 1024 * 1024 else {
            throw PreviewFailure.message("图片数据无效或超过 64 MB，请尝试 SVG 格式。")
        }
        switch format {
        case "svg":
            guard content.hasPrefix("<svg") else { throw PreviewFailure.message("SVG 图片数据无效。") }
            contentType = .svg; data = Data(content.utf8)
        case "png":
            guard let decoded = Data(base64Encoded: content), decoded.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
                throw PreviewFailure.message("PNG 图片数据无效。")
            }
            contentType = .png; data = decoded
        default:
            throw PreviewFailure.message("不支持的图片格式。")
        }
        let base = (name as NSString).lastPathComponent
        filename = ((base as NSString).deletingPathExtension.isEmpty ? "PlantUML" : (base as NSString).deletingPathExtension) + "." + format
    }

    func write(to url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try data.write(to: url, options: .atomic)
    }
}

// A private, read-only origin backed exclusively by files bundled with the extension.
// No HTTP server, file:// directory access, or remote renderer is involved.
final class ResourceHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    private let allowed: Set<String>
    init(bundle: Bundle) {
        root = bundle.resourceURL!.appendingPathComponent("Web")
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: root.path)) ?? []
        allowed = Set(files.filter { ["js", "html", "css"].contains(URL(fileURLWithPath: $0).pathExtension) })
    }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "puml-resource", url.host == "app" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return
        }
        let name = String(url.path.dropFirst())
        guard allowed.contains(name), !name.split(separator: "/").contains("..") else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        do {
            let data = try Data(contentsOf: root.appendingPathComponent(name))
            let mime = name.hasSuffix(".js") ? "text/javascript" : name.hasSuffix(".css") ? "text/css" : "text/html"
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: RendererViewController?
    init(_ target: RendererViewController) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message)
    }
}

class RendererViewController: NSViewController, WKNavigationDelegate {
    private(set) var webView: WKWebView?
    var onResult: (([String: Any]) -> Void)?
    private var watchdog: DispatchWorkItem?
    private var pendingSource = ""
    private var pendingName = ""
    private var savePanel: NSSavePanel?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720))
        preferredContentSize = NSSize(width: 1000, height: 720)
    }

    func preview(file url: URL) {
        do { preview(source: try SourceReader.read(url), name: url.lastPathComponent) }
        catch { showFailure(error.localizedDescription) }
    }

    func preview(source: String, name: String) {
        _ = view
        savePanel?.cancel(nil); savePanel = nil
        watchdog?.cancel()
        webView?.stopLoading()
        view.subviews.forEach { $0.removeFromSuperview() }
        pendingSource = source; pendingName = name
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(ResourceHandler(bundle: Bundle(for: RendererViewController.self)), forURLScheme: "puml-resource")
        config.userContentController.add(WeakMessageHandler(self), name: "preview")
        let web = WKWebView(frame: view.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        web.allowsMagnification = true
        view.addSubview(web)
        webView = web
        startWatchdog()
        // WebKit itself requires a client entitlement in Quick Look. Keep the
        // rendered document offline with an engine-level network block as well
        // as CSP. Compile before loading any content; fail closed on error.
        let rules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "PlantUML-Offline-v1", encodedContentRuleList: rules) { [weak self, weak web] list, error in
            guard let self, let web, web === self.webView else { return }
            guard let list else { self.showFailure(error?.localizedDescription ?? "无法初始化离线渲染规则。"); return }
            web.configuration.userContentController.add(list)
            web.load(URLRequest(url: URL(string: "puml-resource://app/index.html")!))
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.showFailure("预览超过 25 秒。请减少图表内容后重试。") }
        watchdog = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.webView === webView, message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.scheme == "puml-resource",
              message.frameInfo.request.url?.host == "app",
              let body = message.body as? [String: Any], let kind = body["type"] as? String else { return }
        if kind == "ready" {
            webView?.callAsyncJavaScript("window.preview.load(source, filename)",
                arguments: ["source": pendingSource, "filename": pendingName], in: nil, in: .page) { [weak self] result in
                if case .failure(let error) = result { self?.showFailure(error.localizedDescription) }
            }
        } else if kind == "rendering" {
            startWatchdog()
        } else if kind == "result" {
            watchdog?.cancel(); watchdog = nil
            onResult?(body)
        } else if kind == "export" {
            saveImage(body)
        }
    }

    private func saveImage(_ payload: [String: Any]) {
        guard savePanel == nil, let web = webView else { return }
        do {
            let image = try ImageExport(payload)
            let panel = NSSavePanel()
            panel.title = "下载图片"
            panel.prompt = "保存"
            panel.nameFieldStringValue = image.filename
            panel.allowedContentTypes = [image.contentType]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            savePanel = panel
            guard let window = view.window else {
                savePanel = nil
                finishExport("请重新打开预览后再下载。", in: web)
                return
            }
            // Attach to the preview window so Quick Look can host the save sheet.
            panel.beginSheetModal(for: window) { [weak self, weak web] response in
                guard let self, let web, web === self.webView else { return }
                self.savePanel = nil
                guard response == .OK, let url = panel.url else {
                    self.finishExport(response == .cancel ? "" : "无法打开保存窗口，请重试。", in: web)
                    return
                }
                do {
                    try image.write(to: url)
                    self.finishExport("已保存：" + url.lastPathComponent, in: web)
                } catch { self.finishExport("保存失败：" + error.localizedDescription, in: web) }
            }
        } catch { finishExport("下载失败：" + error.localizedDescription, in: web) }
    }

    private func finishExport(_ message: String, in web: WKWebView) {
        web.callAsyncJavaScript("window.preview.exportFinished(message)", arguments: ["message": message], in: nil, in: .page, completionHandler: nil)
    }

    func showFailure(_ message: String) {
        _ = view
        savePanel?.cancel(nil); savePanel = nil
        watchdog?.cancel(); watchdog = nil
        webView?.stopLoading(); webView?.removeFromSuperview(); webView = nil
        view.subviews.forEach { $0.removeFromSuperview() }
        let scroll = NSScrollView(frame: view.bounds.insetBy(dx: 24, dy: 24))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.font = .systemFont(ofSize: 15)
        text.string = "无法预览 PlantUML\n\n" + message
        scroll.documentView = text
        view.addSubview(scroll)
        onResult?(["type": "result", "ok": false, "error": message])
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        decisionHandler(url?.absoluteString == "puml-resource://app/index.html" && navigationAction.navigationType == .other ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView { showFailure(error.localizedDescription) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView { showFailure(error.localizedDescription) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView { showFailure("渲染进程已退出，请重新预览或简化图表。") }
    }
    deinit { watchdog?.cancel(); savePanel?.cancel(nil) }
}
