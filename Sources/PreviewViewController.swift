import QuickLookUI
import AppKit

@objc(PreviewViewController)
final class PreviewViewController: RendererViewController, QLPreviewingController {
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        var completed = false
        onResult = { _ in
            guard !completed else { return }
            completed = true
            // Syntax/encoding errors are displayed inside the preview instead of Finder's generic error.
            handler(nil)
        }
        preview(file: url)
    }
}
