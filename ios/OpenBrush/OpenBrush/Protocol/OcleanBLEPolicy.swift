// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum OcleanBLEPolicy {
    static let service = "8082caa8-41a6-4021-91c6-56f9b954cc18"
    static let sessionTX = "5f78df94-798c-46f5-990a-855b673fbb89"
    static let sessionRX = "5f78df94-798c-46f5-990a-855b673fbb90"
    static let scanSeconds: TimeInterval = 8
    static let collectionSeconds: TimeInterval = 12
    static let totalSeconds: TimeInterval = 75
    static let cleanupSeconds: TimeInterval = 3
    static let maximumNotificationBytes = 512 // Same capture-level bound as Python.
}

enum OcleanBLEError: LocalizedError {
    case wrongIdentity, requestAlreadySent
    var errorDescription: String? {
        switch self {
        case .wrongIdentity: return "Modello o versione non corrispondenti: nessuna richiesta dello storico inviata."
        case .requestAlreadySent: return "La richiesta è già stata inviata. Nessun secondo invio consentito."
        }
    }
}

struct OcleanBLERequestGate {
    private(set) var hasClaimedRequest = false
    mutating func claim(model: String?, software: String?) throws -> Data {
        guard model == "OCLEANY3X", software == "1.0.0.36" else { throw OcleanBLEError.wrongIdentity }
        guard !hasClaimedRequest else { throw OcleanBLEError.requestAlreadySent }
        hasClaimedRequest = true
        return Data([0x03, 0x07])
    }
}

/// Discovery heuristics are not identity verification. DIS remains the write gate.
enum OcleanCandidateMatch: String {
    case advertisedName = "nome-advertising"
    case peripheralName = "nome-periferica"
    case advertisedService = "servizio-advertising"
    case unrelated = "nessun-nome-o-servizio-Oclean"
    var accepted: Bool { self != .unrelated }
}

enum OcleanCandidateSelection: Equatable {
    case none, single(UUID), ambiguous
}

enum OcleanDiscoveryPolicy {
    static func match(localName: String?, peripheralName: String?, serviceUUIDs: [String]) -> OcleanCandidateMatch {
        if localName?.localizedCaseInsensitiveContains("oclean") == true { return .advertisedName }
        if peripheralName?.localizedCaseInsensitiveContains("oclean") == true { return .peripheralName }
        if serviceUUIDs.contains(where: { $0.caseInsensitiveCompare(OcleanBLEPolicy.service) == .orderedSame }) {
            return .advertisedService
        }
        return .unrelated
    }

    static func select(identifiers: [UUID]) -> OcleanCandidateSelection {
        let unique = Set(identifiers)
        guard unique.count == 1, let identifier = unique.first else {
            return unique.isEmpty ? .none : .ambiguous
        }
        return .single(identifier)
    }

    static func failureMessage(_ issue: CaptureIssue?) -> String? {
        switch issue {
        case .scanEmpty: return "Nessun Oclean visto. Risveglia il display, avvicina lo spazzolino e chiudi l’app Oclean prima di premere Sincronizza."
        case .ambiguous: return "Più dispositivi Oclean trovati. Allontana gli altri spazzolini: nessun collegamento eseguito."
        case .connectionUnavailable: return "Oclean trovato, ma il collegamento non è riuscito. Potrebbe essere già collegato a un’altra app. Chiudi Oclean e gli altri collegamenti Bluetooth; poi riprova con Sincronizza."
        default: return nil
        }
    }
}

/// Private app preference, never copied into exported session JSON or diagnostics.
final class OcleanKnownPeripheralStore {
    private let defaults: UserDefaults
    private let key = "it.imix.openbrush.ble.verified-peripheral.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var identifier: UUID? { defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
    func remember(_ identifier: UUID, model: String?, software: String?) {
        guard model == "OCLEANY3X", software == "1.0.0.36" else { return }
        defaults.set(identifier.uuidString, forKey: key)
    }
}
