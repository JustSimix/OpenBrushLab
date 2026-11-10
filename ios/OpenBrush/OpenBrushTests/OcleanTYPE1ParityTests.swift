// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OpenBrush

final class OcleanTYPE1ParityTests: XCTestCase {
    private struct Corpus: Decodable {
        let format: String
        let schema: Int
        let vectors: [Vector]
    }
    private struct Vector: Decodable {
        let id: String
        let deviceKey: String
        let notificationsHex: [String]
        let expected: OcleanTYPE1Result
        enum CodingKeys: String, CodingKey {
            case id, expected
            case deviceKey = "device_key", notificationsHex = "notifications_hex"
        }
    }

    private func bytes(_ hex: String) throws -> Data {
        guard hex.count % 2 == 0 else { throw OpenBrushError.invalidSession }
        var data = Data()
        var start = hex.startIndex
        while start < hex.endIndex {
            let end = hex.index(start, offsetBy: 2)
            guard let value = UInt8(hex[start..<end], radix: 16) else { throw OpenBrushError.invalidSession }
            data.append(value)
            start = end
        }
        return data
    }

    func testEverySharedPythonVectorIncludingExactJSONShape() throws {
        let bundle = Bundle(for: OcleanTYPE1ParityTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "TYPE1Vectors", withExtension: "json"))
        let raw = try Data(contentsOf: url)
        let corpus = try JSONDecoder().decode(Corpus.self, from: raw)
        XCTAssertEqual(corpus.format, "openbrushlab-type1-parity-vectors")
        XCTAssertEqual(corpus.schema, 1)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let rawCases = try XCTUnwrap(root["vectors"] as? [[String: Any]])
        XCTAssertEqual(corpus.vectors.count, rawCases.count)
        for (index, vector) in corpus.vectors.enumerated() {
            let frames = try vector.notificationsHex.map(bytes)
            let result = OcleanTYPE1Decoder.decode(frames, deviceKey: vector.deviceKey)
            XCTAssertEqual(result, vector.expected, vector.id)
            let encoded = try JSONEncoder().encode(result)
            let actualJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
            let expectedJSON = try XCTUnwrap(rawCases[index]["expected"] as? NSDictionary)
            XCTAssertEqual(actualJSON, expectedJSON, "Null e chiavi opzionali: \(vector.id)")
            var assembler = OcleanTYPE1Assembler()
            for frame in frames { assembler.feed(frame) }
            XCTAssertEqual(assembler.result(deviceKey: vector.deviceKey), vector.expected, "Assembler: \(vector.id)")
        }
    }
}
