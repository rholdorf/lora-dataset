import AppKit
import Quartz

/// Minimal QLPreviewPanel data source for context menu Quick Look.
/// Phase 9 will build full QLPreviewPanel infrastructure with spacebar support.
class QLPreviewHelper: NSObject, QLPreviewPanelDataSource {
    var previewURL: URL?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return previewURL as QLPreviewItem?
    }
}
