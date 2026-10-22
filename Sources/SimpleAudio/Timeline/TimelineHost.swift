import AppKit
import SwiftUI

struct TimelineHost: NSViewRepresentable {
    let model: AppModel
    var onCreate: ((TimelineView) -> Void)?

    func makeNSView(context: Context) -> TimelineView {
        let view = TimelineView(model: model)
        model.timelineView = view
        onCreate?(view)
        return view
    }

    func updateNSView(_ view: TimelineView, context: Context) {
        if model.timelineView !== view {
            model.timelineView = view
        }
    }
}
