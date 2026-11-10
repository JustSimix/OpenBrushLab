// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

@MainActor
final class SyncViewModel: ObservableObject {
    @Published private(set) var archive = SessionArchive()
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Chiudi lÃ¢â‚¬â„¢app Oclean e risveglia il display per sincronizzare."
    @Published private(set) var storageBlocked = false
    @Published private(set) var reviewEvents: [String: [StoredBrushEvent]] = [:]
    let bluetooth: OcleanBLEClient?
    private let capture: any OcleanCaptureSource
    private let writer: HealthKitWriter
    private let store: any SessionArchivePersistence
    private var foregroundAttempted = false
    private var foreground = true

    init(capture: any OcleanCaptureSource, writer: HealthKitWriter,
         store: any SessionArchivePersistence, bluetooth: OcleanBLEClient? = nil) {
        self.capture = capture; self.writer = writer; self.store = store; self.bluetooth = bluetooth
        do { archive = try store.load() }
        catch { storageBlocked = true; status = "Archivio non leggibile: sincronizzazione bloccata. Non ÃƒÂ¨ stato sostituito nÃƒÂ© svuotato." }
    }

    static func live() -> SyncViewModel {
        let bluetooth = OcleanBLEClient()
        return SyncViewModel(capture: bluetooth,
            writer: HealthKitWriter(client: HealthKitClient(), receipts: FileReceiptStore()),
            store: SessionArchiveFileStore(), bluetooth: bluetooth)
    }

    var sessions: [ArchivedBrushSession] {
        archive.sessions.values.sorted { ($0.startUTC ?? $0.firstSeen) > ($1.startUTC ?? $1.firstSeen) }
    }

    func enterForeground() async {
        foreground = true
        guard !foregroundAttempted else { return }
        foregroundAttempted = true
        await synchronize()
    }

    func leaveForeground() {
        foreground = false; foregroundAttempted = false
        capture.cancel()
    }

    @discardableResult
    private func persist() -> Bool {
        do { try store.save(archive); return true }
        catch {
            storageBlocked = true
            status = "Salvataggio locale non riuscito: nessun altro invio. Un invio a Salute giÃƒÂ  confermato puÃƒÂ² essere presente; non viene cancellato. Riapri lÃ¢â‚¬â„¢app per rileggere lÃ¢â‚¬â„¢archivio."
            return false
        }
    }

    func synchronize() async {
        guard !isBusy, !storageBlocked, foreground else { return }
        isBusy = true
        defer { isBusy = false }
        status = "Ricerca e letturaÃ¢â‚¬Â¦ Risveglia ora il display e tieni lo spazzolino vicino."
        do {
            let envelope = try await capture.acquire()
            try SessionNormalizer.ingest(envelope, into: &archive)
            guard persist() else { return } // Permanent history BEFORE HealthKit.
            guard foreground else { status = "Acquisizione conservata. Riprendi dallÃ¢â‚¬â„¢app in primo piano."; return }
            if !envelope.transportCompleted {
                status = "Lettura non conclusa. Chiudi Oclean; controlla vicinanza, display e Bluetooth. Nessun nuovo tentativo automatico."
                return
            }
            if writer.client.writeAuthorization == .notDetermined {
                try await writer.requestAuthorization()
            }
            guard foreground else { return }
            guard writer.client.writeAuthorization == .authorized else {
                status = "Sessioni conservate. Autorizza la scrittura in Salute per esportare quelle attendibili."; return
            }
            for id in archive.sessions.keys.sorted() {
                guard foreground, !storageBlocked else { break }
                await deliver(id)
            }
            if !storageBlocked { status = "Lettura terminata. Le sessioni attendibili sono state elaborate; controlla gli eventuali avvisi e quelle in revisione." }
        } catch { status = "Sincronizzazione non completata: " + error.localizedDescription }
    }

    func authorize() async {
        guard !isBusy, !storageBlocked else { return }
        isBusy = true; defer { isBusy = false }
        do {
            try await writer.requestAuthorization()
            guard foreground else { return }
            for id in archive.sessions.keys.sorted() {
                guard foreground, !storageBlocked else { break }
                await deliver(id)
            }
        } catch { status = error.localizedDescription }
    }

    private func deliver(_ id: String, allowOverlap: Bool = false) async {
        guard foreground, var entry = archive.sessions[id], entry.canExport,
              let session = try? entry.healthSession() else { return }
        if let delivery = entry.delivery, delivery.version >= session.syncVersion,
           delivery.payloadHash == session.payloadHash,
           delivery.state == .verified || delivery.state == .acceptedUnverified { return }
        entry.delivery = SessionDelivery(state: .pending, version: session.syncVersion,
            payloadHash: session.payloadHash, recordedAt: Date())
        archive.sessions[id] = entry
        guard persist() else { return }
        do {
            let outcome = try await writer.write(session, allowForeignOverlap: allowOverlap,
                shouldProceed: { [weak self] in self?.foreground == true && self?.storageBlocked == false })
            switch outcome {
            case .written, .alreadyPresent, .versionUpdated:
                entry.delivery?.state = .verified
                reviewEvents[id] = nil
            case .alreadySubmittedLocally, .submittedNotVerified:
                entry.delivery?.state = .acceptedUnverified
            case .foreignConfirmationRequired(let events):
                entry.delivery = nil
                entry.reviewReasons.append(.overlappingHealthEvent)
                reviewEvents[id] = events
            case .savedButReceiptFailed, .saveAcceptedNeedsReview:
                entry.delivery?.state = .needsReview
                entry.reviewReasons.append(.deliveryUncertain)
            }
            archive.sessions[id] = entry
            _ = persist()
        } catch {
            // Retain pending: after interruption a fresh preflight and receipt lookup recover safely.
            status = "Invio da verificare: " + error.localizedDescription
        }
    }

    func selectVariant(id: String, fingerprint: String) {
        guard !isBusy, !storageBlocked, var entry = archive.sessions[id], entry.variants[fingerprint] != nil else { return }
        entry.selectedFingerprint = fingerprint; entry.reviewedAt = Date()
        SessionNormalizer.refresh(&entry, boundDeviceKey: archive.boundDeviceKey)
        if entry.canExport, let payload = try? entry.healthSession().payloadHash {
            if let old = entry.lastProposedPayloadHash, old != payload { entry.syncVersion += 1 }
            entry.lastProposedPayloadHash = payload
        }
        archive.sessions[id] = entry; _ = persist()
        status = "Scelta conservata. I controlli su data, durata e orologio restano attivi."
    }

    func noteClockReference(id: String, phoneStart: Date) {
        guard !isBusy, !storageBlocked, var entry = archive.sessions[id], let start = entry.startUTC else { return }
        let reference = ClockReference(sessionID: id, deviceStartUTC: start,
            observedPhoneStartUTC: phoneStart, notedAt: Date())
        archive.clockReferences[entry.deviceKey] = reference
        // A later good reference must not automatically rehabilitate older, suspect records.
        entry.estimatedClockDriftSeconds = reference.driftSeconds; entry.reviewedAt = Date()
        SessionNormalizer.refresh(&entry, boundDeviceKey: archive.boundDeviceKey)
        archive.sessions[id] = entry; _ = persist()
        status = "Riferimento conservato: nessun timestamp modificato e nessuna correzione Bluetooth."
    }

    func review(id: String, confirmOverlap: Bool = false) async {
        guard !isBusy, !storageBlocked, foreground, var entry = archive.sessions[id] else { return }
        isBusy = true; defer { isBusy = false }
        entry.reviewedAt = Date()
        // A new preflight will block again unless the user explicitly confirms the overlap.
        entry.reviewReasons.removeAll { $0 == .overlappingHealthEvent }
        SessionNormalizer.refresh(&entry, boundDeviceKey: archive.boundDeviceKey)
        archive.sessions[id] = entry
        guard persist() else { return }
        if entry.canExport { await deliver(id, allowOverlap: confirmOverlap) }
        else { status = "Revisione annotata. I motivi di blocco richiedono dati attendibili; non sono aggirati." }
    }
}
