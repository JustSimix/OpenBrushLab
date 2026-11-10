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

    func testOcleanAdvertisingNameWithoutServiceIsAccepted() {
        XCTAssertEqual(OcleanDiscoveryPolicy.match(localName: "Oclean X Pro Elite",
            peripheralName: nil, serviceUUIDs: []), .advertisedName)
        XCTAssertTrue(OcleanDiscoveryPolicy.match(localName: "OCLEAN X Pro Elite",
            peripheralName: nil, serviceUUIDs: []).accepted)
    }

    func testPeripheralNameIsCheckedEvenIfAdvertisingNameIsUnrelated() {
        XCTAssertEqual(OcleanDiscoveryPolicy.match(localName: "Altro nome",
            peripheralName: "oclean X Pro Elite", serviceUUIDs: []), .peripheralName)
    }

    func testOnlyAdvertisedServiceIsAcceptedCaseInsensitively() {
        XCTAssertEqual(OcleanDiscoveryPolicy.match(localName: nil, peripheralName: nil,
            serviceUUIDs: [OcleanBLEPolicy.service.uppercased()]), .advertisedService)
    }

    func testUnrelatedDeviceAndMissingNamesAreDiscarded() {
        for name in [nil, "Cuffie Bluetooth"] as [String?] {
            XCTAssertEqual(OcleanDiscoveryPolicy.match(localName: name,
                peripheralName: name, serviceUUIDs: ["180F"]), .unrelated)
            XCTAssertFalse(OcleanDiscoveryPolicy.match(localName: name,
                peripheralName: name, serviceUUIDs: []).accepted)
        }
    }

    func testTwoDistinctCandidatesAreAmbiguous() {
        XCTAssertEqual(OcleanDiscoveryPolicy.select(identifiers: [UUID(), UUID()]), .ambiguous)
    }

    func testSamePeripheralFromTwoRetrievalPathsCountsOnce() {
        let identifier = UUID()
        XCTAssertEqual(OcleanDiscoveryPolicy.select(identifiers: [identifier, identifier]), .single(identifier))
    }

    func testNoCandidatesMeansNone() {
        XCTAssertEqual(OcleanDiscoveryPolicy.select(identifiers: []), .none)
    }

    func testKnownIdentifierSavedOnlyAfterExactDISAndSurvivesNewStore() throws {
        let suite = "it.imix.openbrush.discovery-test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OcleanKnownPeripheralStore(defaults: defaults)
        let identifier = UUID()
        XCTAssertNil(store.identifier)
        store.remember(identifier, model: "OCLEANY3X", software: "1.0.0.35")
        store.remember(identifier, model: "OCLEANY3P", software: "1.0.0.36")
        store.remember(identifier, model: nil, software: nil)
        XCTAssertNil(store.identifier)
        store.remember(identifier, model: "OCLEANY3X", software: "1.0.0.36")
        XCTAssertEqual(OcleanKnownPeripheralStore(defaults: defaults).identifier, identifier)
        store.remember(UUID(), model: "wrong", software: "wrong")
        XCTAssertEqual(store.identifier, identifier)
    }

    func testDiscoveryMessagesDistinguishNoDeviceAmbiguityAndConnectionFailure() throws {
        let unseen = try XCTUnwrap(OcleanDiscoveryPolicy.failureMessage(.scanEmpty))
        let ambiguous = try XCTUnwrap(OcleanDiscoveryPolicy.failureMessage(.ambiguous))
        let occupied = try XCTUnwrap(OcleanDiscoveryPolicy.failureMessage(.connectionUnavailable))
        XCTAssertTrue(unseen.contains("Nessun Oclean visto"))
        XCTAssertTrue(ambiguous.contains("Più dispositivi"))
        XCTAssertTrue(occupied.contains("Oclean trovato"))
        XCTAssertTrue(occupied.contains("Potrebbe")) // Never claim which app owns the connection.
        XCTAssertNotEqual(unseen, ambiguous)
        XCTAssertNotEqual(unseen, occupied)
        XCTAssertNil(OcleanDiscoveryPolicy.failureMessage(.cancelled))
    }
}
