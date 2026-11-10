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
