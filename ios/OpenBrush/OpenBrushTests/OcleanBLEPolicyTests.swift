// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import OpenBrush

final class OcleanBLEPolicyTests: XCTestCase {
    func testWrongIdentityNeverClaimsARequest() {
        for (model, version) in [("OCLEANY3P", "1.0.0.36"), ("OCLEANY3X", "1.0.0.35"), ("", "")] {
            var gate = OcleanBLERequestGate()
            XCTAssertThrowsError(try gate.claim(model: model, software: version))
            XCTAssertFalse(gate.hasClaimedRequest)
        }
    }

    func testExactIdentityAllowsOnlyOneRequest() throws {
        var gate = OcleanBLERequestGate()
        XCTAssertEqual(try gate.claim(model: "OCLEANY3X", software: "1.0.0.36"), Data([0x03, 0x07]))
        XCTAssertTrue(gate.hasClaimedRequest)
        XCTAssertThrowsError(try gate.claim(model: "OCLEANY3X", software: "1.0.0.36"))
    }

    func testCapturePolicyBoundsMatchPython() {
        XCTAssertEqual(OcleanBLEPolicy.collectionSeconds, 12)
        XCTAssertEqual(OcleanBLEPolicy.totalSeconds, 75)
        XCTAssertEqual(OcleanTYPE1Decoder.maximumNotifications, 256)
        XCTAssertEqual(OcleanTYPE1Decoder.maximumBytes, 8192)
        XCTAssertEqual(OcleanBLEPolicy.maximumNotificationBytes, 512)
    }
}
