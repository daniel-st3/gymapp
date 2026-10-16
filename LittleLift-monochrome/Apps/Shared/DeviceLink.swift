import Foundation
import WatchConnectivity

/// Context carries the latest state. Live messages provide a persisted reply.
/// The store's durable outbox remains authoritative until the phone acknowledges it.
@MainActor
final class DeviceLink: NSObject, WCSessionDelegate {
    var onMessage: ((SyncMessage) throws -> SyncMessage?)?
    var onMotionFile: ((Data) throws -> Void)?
    var onReady: (() -> Void)?
    var onStatus: ((String) -> Void)?
    var onBusy: ((Bool) -> Void)?
    var onDetails: ((String) -> Void)?
    private let session: WCSession?
    private var latestSnapshot: PhoneSnapshot?
    private var wantsSnapshot = false
    private var pending: [String: (id: UUID, timeout: Task<Void, Never>)] = [:]

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    func activate() {
        guard let session else { onStatus?("Watch connection is unavailable on this device."); return }
        session.delegate = self
        if session.activationState != .activated { session.activate() }
        updateDetails()
    }

    func publish(_ snapshot: PhoneSnapshot) throws {
        latestSnapshot = snapshot
        _ = try SyncCodec.encode(.snapshot(snapshot))
        guard let session else { onStatus?("Watch connection is unavailable."); return }
        guard session.activationState == .activated else {
            onStatus?("Connecting to watch…"); activate(); return
        }
        #if os(iOS)
        guard session.isPaired else { onStatus?("This iPhone has no paired watch."); return }
        guard session.isWatchAppInstalled else {
            onStatus?("Install and open Little Lift on the paired watch."); return
        }
        #endif
        // A fresh ID makes an explicit resend meaningful even for the same plan.
        try session.updateApplicationContext(payload(.snapshot(snapshot)))
        updateDetails()
        if session.isReachable {
            onStatus?("Sending workout to watch…")
            try sendLive(.snapshot(snapshot), key: "plan")
        } else { onStatus?("Saved on iPhone. Waiting for Little Lift on the paired watch.") }
    }

    func enqueue(_ workout: WorkoutSession) throws {
        guard let session, session.activationState == .activated else {
            onStatus?("Workout saved. Connecting to iPhone…"); activate(); return
        }
        let message = SyncMessage.completed(workout)
        #if !targetEnvironment(simulator)
        let alreadyQueued = session.outstandingUserInfoTransfers.contains { transfer in
            guard let data = transfer.userInfo["littlelift"] as? Data,
                  let packet = try? SyncCodec.decode(data), case .completed(let queued) = packet else { return false }
            return queued.id == workout.id
        }
        if !alreadyQueued { session.transferUserInfo(try payload(message)) }
        #endif
        // The simulator can exercise foreground delivery without depending on
        // background user-info transfers. The real watch retains both paths.
        if session.isReachable { try sendLive(message, key: "workout:\(workout.id)") }
        else { onStatus?("Workout saved on watch. Open Little Lift on the paired iPhone to sync.") }
    }

    func sendMotionFile(_ url: URL, id: UUID) throws {
        guard let session, session.activationState == .activated else { throw WorkoutError.invalidState("Open both apps and retry motion transfer.") }
        guard !session.outstandingFileTransfers.contains(where: { $0.file.metadata?["motionID"] as? String == id.uuidString }) else { return }
        session.transferFile(url, metadata: ["kind": "littlelift.motion.v1", "motionID": id.uuidString])
        onStatus?("Motion replay queued. The original stays on Watch.")
    }
    func requestSnapshot() {
        wantsSnapshot = true
        guard let session else { onStatus?("iPhone connection is unavailable."); return }
        guard session.activationState == .activated else {
            onStatus?("Connecting to iPhone…"); activate(); return
        }
        wantsSnapshot = false
        updateDetails()
        onStatus?("Requesting workout from iPhone…")
        do {
            // A watch-originated message can wake the phone app. An explicit
            // attempt gets an error callback instead of silently returning.
            try sendLive(.requestSnapshot, key: "request")
        } catch { onStatus?(error.localizedDescription) }
    }

    private func payload(_ message: SyncMessage) throws -> [String: Any] {
        ["littlelift": try SyncCodec.encode(message), "deliveryID": UUID().uuidString]
    }

    private func sendLive(_ message: SyncMessage, key: String) throws {
        guard let session, session.activationState == .activated else {
            onStatus?("Connection is still starting. Please retry in a moment.")
            activate(); return
        }
        guard pending[key] == nil else { return }
        let packet = try payload(message)
        let id = UUID()
        let timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.finish(key: key, id: id) else { return }
            self.onStatus?("No reply yet. Keep Little Lift open on both paired devices and retry.")
            self.updateDetails()
        }
        pending[key] = (id, timeout)
        onBusy?(true)
        session.sendMessage(packet, replyHandler: { [weak self] reply in
            let data = reply["littlelift"] as? Data
            let error = reply["error"] as? String
            let accepted = reply["accepted"] as? Bool ?? false
            Task { @MainActor in
                guard let self, self.finish(key: key, id: id) else { return }
                if let error { self.onStatus?(error) }
                else if let data { self.receive(data) }
                else if !accepted { self.onStatus?("The other app returned an invalid sync reply.") }
                self.updateDetails()
            }
        }, errorHandler: { [weak self] error in
            let detail = error.localizedDescription
            Task { @MainActor in
                guard let self, self.finish(key: key, id: id) else { return }
                self.onStatus?("Couldn’t reach the other app. Open Little Lift on both paired devices. \(detail)")
                self.updateDetails()
            }
        })
    }

    @discardableResult private func finish(key: String, id: UUID) -> Bool {
        guard let request = pending[key], request.id == id else { return false }
        request.timeout.cancel(); pending.removeValue(forKey: key)
        onBusy?(!pending.isEmpty); return true
    }

    private func receive(_ data: Data, replyHandler: (([String: Any]) -> Void)? = nil) {
        do {
            let message = try SyncCodec.decode(data)
            guard let handler = onMessage else { throw WorkoutError.invalidState("The other app is still starting.") }
            let response = try handler(message)
            // Stores return only after their candidate state has been saved.
            if let replyHandler {
                if let response { replyHandler(try payload(response)) }
                else { replyHandler(["accepted": true]) }
            } else if let response {
                switch response {
                case .snapshot(let snapshot): try publish(snapshot)
                case .planReceived(let id):
                    if session?.isReachable == true { try sendLive(.planReceived(id), key: "receipt:\(id)") }
                default: break
                }
            }
        } catch {
            onStatus?(error.localizedDescription)
            replyHandler?(["error": error.localizedDescription])
        }
    }

    private func becameReady(cached: Data? = nil) {
        if let cached { receive(cached) }
        if let latestSnapshot { do { try publish(latestSnapshot) } catch { onStatus?(error.localizedDescription) } }
        if wantsSnapshot { requestSnapshot() }
        updateDetails(); onReady?()
    }

    private func updateDetails() {
        guard let session else { onDetails?("WatchConnectivity is unavailable."); return }
        var lines = ["App: \(Bundle.main.bundleIdentifier ?? "unknown")",
                     "Session: \(session.activationState == .activated ? "active" : "connecting")",
                     "Other app reachable: \(session.isReachable ? "yes" : "no")"]
        #if os(iOS)
        lines.append("Watch paired: \(session.isPaired ? "yes" : "no")")
        lines.append("Watch app installed: \(session.isWatchAppInstalled ? "yes" : "no")")
        #endif
        #if targetEnvironment(simulator)
        lines.append("Running in Simulator")
        #endif
        onDetails?(lines.joined(separator: "\n"))
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let cached = session.receivedApplicationContext["littlelift"] as? Data
        let message = error?.localizedDescription
        Task { @MainActor [weak self] in
            if let message { self?.onStatus?(message) }
            else { self?.becameReady(cached: cached) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["littlelift"] as? Data else { return }
        Task { @MainActor [weak self] in self?.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo["littlelift"] as? Data else { return }
        Task { @MainActor [weak self] in self?.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["littlelift"] as? Data else { return }
        Task { @MainActor [weak self] in self?.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message["littlelift"] as? Data else { replyHandler(["error": "Missing sync payload."]); return }
        Task { @MainActor [weak self] in
            guard let self else { replyHandler(["error": "The other app is not ready."]); return }
            self.receive(data, replyHandler: replyHandler)
        }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["kind"] as? String == "littlelift.motion.v1" else { return }
        do {
            let size = try file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2_000_000 else { return }
            // Read within the delegate call; Apple's temporary file expires on return.
            let data = try InputBoundary.read(file.fileURL, maximumBytes: 2_000_000)
            Task { @MainActor [weak self] in
                do { try self?.onMotionFile?(data) }
                catch { self?.onStatus?("Motion replay preserved on Watch: \(error.localizedDescription)") }
            }
        } catch { Task { @MainActor [weak self] in self?.onStatus?(error.localizedDescription) } }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.updateDetails()
            if reachable { self?.becameReady() }
        }
    }
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let message = error?.localizedDescription {
            Task { @MainActor [weak self] in self?.onStatus?("Saved locally. Sync will retry: \(message)") }
        }
    }
    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.becameReady() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
