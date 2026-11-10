// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@MainActor
protocol SessionArchivePersistence: AnyObject {
    func load() throws -> SessionArchive
    func save(_ archive: SessionArchive) throws
}

@MainActor
final class SessionArchiveFileStore: SessionArchivePersistence {
    private let directory: URL?
    private var file: URL? { directory?.appendingPathComponent("session-archive-v1.json") }
    init(base: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first) {
        directory = base?.appendingPathComponent("OpenBrush", isDirectory: true)
    }
    func load() throws -> SessionArchive {
        guard let file else { throw OpenBrushError.localStorageUnavailable }
        guard FileManager.default.fileExists(atPath: file.path) else { return SessionArchive() }
        let data = try Data(contentsOf: file)
        guard data.count <= 32*1024*1024 else { throw OpenBrushError.receiptCorrupted }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(SessionArchive.self, from: data)
        guard archive.format == "openbrush-ios-session-archive", archive.schema == 1,
              archive.trustProfile == "OCLEANY3X-1.0.0.36-P01",
              archive.sessions.allSatisfy({ $0.key == $0.value.id && $0.value.syncVersion > 0 }) else {
            throw OpenBrushError.receiptCorrupted
        }
        for entry in archive.sessions.values {
            guard !entry.variants.isEmpty,
                  entry.deviceKey.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
                  entry.selectedFingerprint.map({ entry.variants[$0] != nil }) ?? true else {
                throw OpenBrushError.receiptCorrupted
            }
            for (fingerprint, record) in entry.variants {
                guard fingerprint == record.recordFingerprint,
                      try SessionNormalizer.identity(deviceKey: entry.deviceKey, record: record) == entry.id else {
                    throw OpenBrushError.receiptCorrupted
                }
            }
        }
        return archive
    }
    func save(_ archive: SessionArchive) throws {
        guard var directory, let file else { throw OpenBrushError.localStorageUnavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var flags = URLResourceValues(); flags.isExcludedFromBackup = false
        try directory.setResourceValues(flags) // Permanent history, not an expendable cache.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= 32*1024*1024 else { throw OpenBrushError.localStorageUnavailable }
        try data.write(to: file, options: [.atomic, .completeFileProtection])
    }
}
