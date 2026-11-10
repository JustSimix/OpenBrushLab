// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

enum SessionHash {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func canonical(_ value: [Any]) throws -> String {
        hex(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]))
    }
    static func deviceKey(peripheralID: UUID) -> String {
        hex(Data(("openbrush:corebluetooth-device:v1:" + peripheralID.uuidString.lowercased()).utf8))
    }
}

enum CaptureIssue: String, Codable, Sendable {
    case connectionUnavailable, securityReported, timeout, cancelled, ambiguous, scanEmpty, other
}

struct OcleanCaptureEnvelope: Codable, Sendable {
    let deviceKey: String
    let capturedAt: Date
    let result: OcleanTYPE1Result
    let transportCompleted: Bool
    var issue: CaptureIssue?
    var estimatedClockDriftSeconds: Double?

    var id: String {
        let parts = [deviceKey, String(capturedAt.timeIntervalSince1970), result.status.rawValue,
                     String(transportCompleted), result.records.map(\.recordFingerprint).joined(separator: ",")]
        return SessionHash.hex(Data(parts.joined(separator: "|").utf8))
    }
}

@MainActor
protocol OcleanCaptureSource: AnyObject {
    func acquire() async throws -> OcleanCaptureEnvelope
    func cancel()
}

enum SessionReviewReason: String, Codable, CaseIterable {
    case invalidDate, unknownTimezone, timezoneMismatch, nonexistentLocalTime
    case incompleteRecord, incompleteTransport, durationInvalid, voidScore, tooShort
    case conflictingVariants, futureEnd, clockDrift, differentDevice
    case overlappingHealthEvent, deliveryUncertain

    var message: String {
        switch self {
        case .invalidDate: return "Data dello spazzolino non attendibile: nessuna interpolazione applicata."
        case .unknownTimezone: return "Indice del fuso orario sconosciuto."
        case .timezoneMismatch: return "Il fuso del record non coincide con Europe/Rome alla data indicata."
        case .nonexistentLocalTime: return "Orario locale inesistente nel cambio all'ora legale."
        case .incompleteRecord: return "Frammento incompleto: non rappresenta una sessione completa."
        case .incompleteTransport: return "Nessuna ricezione completa ha confermato questo record."
        case .durationInvalid: return "Durata non attendibile o superiore a quella programmata."
        case .voidScore: return "Il dispositivo ha marcato la sessione con score 1."
        case .tooShort: return "Durata di 14 secondi o meno: da rivedere."
        case .conflictingVariants: return "Varianti diverse della stessa identitÃƒÂ : seleziona quella verificata."
        case .futureEnd: return "La fine calcolata supera l'ora di lettura dell'iPhone di oltre 5 secondi."
        case .clockDrift: return "Deriva stimata dell'orologio superiore a 2 minuti. Nessuna correzione inviata."
        case .differentDevice: return "IdentitÃƒÂ  locale diversa dallo spazzolino giÃƒÂ  archiviato: associazione da verificare."
        case .overlappingHealthEvent: return "Un altro evento leggibile occupa questo intervallo: serve una revisione."
        case .deliveryUncertain: return "Salute puÃƒÂ² aver accettato il dato, ma la verifica non ÃƒÂ¨ conclusa."
        }
    }
}

struct SessionSourceStamp: Codable {
    let capturedAt: Date
    let transportCompleted: Bool
    let fingerprints: Set<String>
}

struct SessionDelivery: Codable {
    enum State: String, Codable { case pending, verified, acceptedUnverified, needsReview }
    var state: State
    let version: Int
    let payloadHash: String
    let recordedAt: Date
}

struct ArchivedBrushSession: Codable, Identifiable {
    let id: String // Derived identity, NOT a record ID provided by TYPE1.
    let deviceKey: String
    var variants: [String: OcleanTYPE1Record]
    var sources: [String: SessionSourceStamp]
    var confirmedFingerprints: Set<String>
    var selectedFingerprint: String?
    var firstSeen: Date
    var lastSeen: Date
    var reviewReasons: [SessionReviewReason] = []
    var startUTC: Date?
    var endUTC: Date?
    var syncVersion = 1
    var lastProposedPayloadHash: String?
    var estimatedClockDriftSeconds: Double?
    var delivery: SessionDelivery?
    var reviewedAt: Date?

    var selectedRecord: OcleanTYPE1Record? {
        if let selectedFingerprint { return variants[selectedFingerprint] }
        return variants.count == 1 ? variants.values.first : nil
    }
    var representativeRecord: OcleanTYPE1Record? {
        selectedRecord ?? variants.sorted(by: { $0.key < $1.key }).first?.value
    }
    var syncIdentifier: String { "openbrushlab:toothbrushing:v1:" + id }
    var canExport: Bool { reviewReasons.isEmpty && selectedRecord != nil && startUTC != nil && endUTC != nil }
    var stateText: String {
        if reviewReasons.contains(.conflictingVariants) { return "In conflitto" }
        if !reviewReasons.isEmpty { return "In revisione" }
        if let delivery, delivery.version != syncVersion || delivery.payloadHash != lastProposedPayloadHash { return "Aggiornamento da sincronizzare" }
        switch delivery?.state {
        case .verified: return "Sincronizzata"
        case .acceptedUnverified: return "Inviata, verifica in Salute"
        case .pending: return "Invio da verificare"
        case .needsReview: return "Esito da rivedere"
        case nil: return "Da sincronizzare"
        }
    }
    func healthSession() throws -> BrushSession {
        guard let record = selectedRecord, let startUTC, let endUTC, canExport else { throw OpenBrushError.invalidSession }
        return try BrushSession(startUTC: startUTC, endUTC: endUTC,
            durationSeconds: record.actualDurationCandidateS, timeZoneIdentifier: "Europe/Rome",
            syncIdentifier: syncIdentifier, syncVersion: syncVersion)
    }
}

struct CaptureAudit: Codable {
    let deviceKey: String
    let capturedAt: Date
    let status: TYPE1Status
    let declaredCount: Int?
    let recordFingerprints: [String]
    let transportCompleted: Bool
    let issue: CaptureIssue?
}

struct ClockReference: Codable {
    let sessionID: String
    let deviceStartUTC: Date
    let observedPhoneStartUTC: Date
    let notedAt: Date
    var driftSeconds: Double { deviceStartUTC.timeIntervalSince(observedPhoneStartUTC) }
}

struct SyncWarning: Codable, Identifiable, Equatable {
    let code: String
    let message: String
    var id: String { code }
}

struct SessionArchive: Codable {
    var format = "openbrush-ios-session-archive"
    var schema = 1
    var trustProfile = "OCLEANY3X-1.0.0.36-P01"
    var boundDeviceKey: String?
    var sessions: [String: ArchivedBrushSession] = [:]
    var captures: [String: CaptureAudit] = [:]
    var clockReferences: [String: ClockReference] = [:]
    var warnings: [SyncWarning] = []
}
