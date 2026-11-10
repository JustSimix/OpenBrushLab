// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct WriteReceipt: Codable, Equatable {
    let version: Int
    let payloadHash: String
}

@MainActor
protocol ReceiptStore: AnyObject {
    func receipt(for identifier: String) throws -> WriteReceipt?
    func set(_ receipt: WriteReceipt, for identifier: String) throws
}

@MainActor
final class FileReceiptStore: ReceiptStore {
    private let directory: URL?
    private var file: URL? { directory?.appendingPathComponent("health-write-receipts-v1.json") }

    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first) {
        self.directory = directory?.appendingPathComponent("OpenBrush", isDirectory: true)
    }

    private func load() throws -> [String: WriteReceipt] {
        guard let file else { throw OpenBrushError.localStorageUnavailable }
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        do {
            let values = try JSONDecoder().decode([String: WriteReceipt].self, from: Data(contentsOf: file))
            guard values.values.allSatisfy({ $0.version > 0 && $0.payloadHash.count == 64 }) else {
                throw OpenBrushError.receiptCorrupted
            }
            return values
        } catch { throw OpenBrushError.receiptCorrupted }
    }

    func receipt(for identifier: String) throws -> WriteReceipt? { try load()[identifier] }

    func set(_ receipt: WriteReceipt, for identifier: String) throws {
        guard var directory, let file else { throw OpenBrushError.localStorageUnavailable }
        var values = try load()
        values[identifier] = receipt
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = false
        try directory.setResourceValues(flags)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(values).write(to: file, options: [.atomic, .completeFileProtection])
        var receiptURL = file
        flags.isExcludedFromBackup = true
        try receiptURL.setResourceValues(flags)
    }
}
