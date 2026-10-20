import Foundation

@MainActor
final class APIServer {
    private unowned let model: AppModel
    private var server: HTTPServer?
    let events = APIEvents()

    init(model: AppModel) {
        self.model = model
    }

    @discardableResult
    func start(port: UInt16) -> Bool {
        stop()
        let events = self.events
        let model = self.model
        let http = HTTPServer(
            handler: { req in
                await MainActor.run {
                    APIRouter.handle(req, model: model)
                }
            },
            sseHandler: { fd in
                events.addClient(fd: fd)
            }
        )
        let ok = http.start(port: port)
        if ok {
            self.server = http
            model.apiPort = http.port
            model.apiListening = true
        } else {
            model.apiListening = false
        }
        return ok
    }

    func stop() {
        events.closeAll()
        server?.stop()
        server = nil
        model.apiListening = false
    }

    func notifyStateChanged() {
        events.broadcast(event: "state", payload: APIRouter.stateDict(model: model))
    }
}
