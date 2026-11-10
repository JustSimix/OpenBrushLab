// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

struct BrushSession: Equatable, Sendable {
    let startUTC: Date
    let endUTC: Date
    let durationSeconds: Int
    let timeZoneIdentifier: String
    let syncIdentifier: String
    let syncVersion: Int
    let isTestFixture: Bool

    init(startUTC: Date, endUTC: Date, durationSeconds: Int,
         timeZoneIdentifier: String, syncIdentifier: String, syncVersion: Int, isTestFixture: Bool = false) throws {
        guard (1...7200).contains(durationSeconds),
              startUTC.timeIntervalSince1970.isFinite, endUTC.timeIntervalSince1970.isFinite,
              abs(endUTC.timeIntervalSince(startUTC) - Double(durationSeconds)) < 0.001,
              TimeZone.knownTimeZoneIdentifiers.contains(timeZoneIdentifier),
              syncVersion > 0,
              syncIdentifier.range(of: #"^openbrushlab:toothbrushing:v1:[0-9a-f]{64}$"#,
                                   options: .regularExpression) != nil else {
            throw OpenBrushError.invalidSession
        }
        self.startUTC = startUTC
        self.endUTC = endUTC
        self.durationSeconds = durationSeconds
        self.timeZoneIdentifier = timeZoneIdentifier
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.isTestFixture = isTestFixture
    }

    // Local receipt comparison only. Sync identity uses SynchronizationIdentity below.
    var payloadHash: String {
        let payload = [String(startUTC.timeIntervalSince1970), String(endUTC.timeIntervalSince1970),
                       String(durationSeconds), timeZoneIdentifier, syncIdentifier]
        return SHA256.hash(data: Data(payload.joined(separator: "|").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

enum SynchronizationIdentity {
    /// Python event_id -> SHA256(canonical JSON([namespace, identity])) -> sync prefix.
    /// Scope: full records with a valid local date. No invalid/inline-record fallback here.
    static func make(deviceKey: String, deviceLocalTimestamp: String,
                     timezoneWireIndex: Int, scheme: Int) throws -> String {
        guard deviceKey.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              deviceLocalTimestamp.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$"#,
                                         options: .regularExpression) != nil,
              (1...33).contains(timezoneWireIndex), (0...255).contains(scheme) else {
            throw OpenBrushError.invalidSession
        }
        let identity: [Any] = [deviceKey, deviceLocalTimestamp, timezoneWireIndex, scheme]
        let array: [Any] = ["openbrushlab-session-v1", identity]
        let data = try JSONSerialization.data(withJSONObject: array,
                                              options: [.sortedKeys, .withoutEscapingSlashes])
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "openbrushlab:toothbrushing:v1:" + hash
    }
}

enum OpenBrushError: LocalizedError {
    case invalidSession, healthUnavailable, writeNotAuthorized, authorizationFailed
    case conflictingSamples, sameVersionDifferentPayload, busy, receiptCorrupted
    case localStorageUnavailable, queryFailed, saveFailed, operationCancelled

    var errorDescription: String? {
        switch self {
        case .invalidSession: return "Dati della pulizia non validi. Nessuna scrittura eseguita."
        case .healthUnavailable: return "Salute non Ã¨ disponibile su questo dispositivo."
        case .writeNotAuthorized: return "La scrittura delle pulizie non Ã¨ autorizzata. Controlla i permessi in Salute."
        case .authorizationFailed: return "La richiesta dei permessi Salute non Ã¨ stata completata."
        case .conflictingSamples: return "Campioni o versioni incoerenti: verifica i dati in Salute. Nessuna cancellazione eseguita."
        case .sameVersionDifferentPayload: return "Lo stesso identificativo e la stessa versione hanno dati diversi. Serve una versione piÃ¹ alta."
        case .busy: return "Un salvataggio Ã¨ giÃ  in corso."
        case .receiptCorrupted: return "La ricevuta locale non Ã¨ leggibile. Verifica Salute prima di riprovare."
        case .localStorageUnavailable: return "L'archivio locale non Ã¨ disponibile. Sblocca l'iPhone e riprova."
        case .queryFailed: return "Non Ã¨ stato possibile leggere gli eventi da Salute. Nessuna nuova scrittura eseguita."
        case .operationCancelled: return "Operazione interrotta: riporta l’app in primo piano per sincronizzare."
        case .saveFailed: return "Salute non ha confermato il salvataggio. Controlla i permessi e riprova."
        }
    }
}
