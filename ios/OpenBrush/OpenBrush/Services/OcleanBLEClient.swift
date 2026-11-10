// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine
import CoreBluetooth
import OSLog

/// All operations and delegate callbacks run on CBCentralManager's main queue.
/// Manager creation and scan happen on a foreground synchronization request.
final class OcleanBLEClient: NSObject, ObservableObject {
    @Published private(set) var status = "Nessuna acquisizione Bluetooth avviata."
    @Published private(set) var isBusy = false
    @Published private(set) var notificationCount = 0
    @Published private(set) var receivedBytes = 0
    @Published private(set) var lastResult: OcleanTYPE1Result?
    @Published private(set) var transportCompleted = false

    private enum Phase {
        case idle, waitingForPower, scanning, connecting, services, characteristics
        case identity, subscribing, awaitingWriteResponse, collecting, cleaning
    }
    private var phase = Phase.idle
    private var captureCompletion: ((OcleanCaptureEnvelope) -> Void)?
    private var attemptDeviceKey = "unavailable"
    private var captureIssue: CaptureIssue?
    private var attemptID = UUID()
    private var central: CBCentralManager?
    private var target: CBPeripheral?
    private var candidates: [UUID: CBPeripheral] = [:]
    private let knownPeripheral = OcleanKnownPeripheralStore()
    private let logger = Logger(subsystem: "it.imix.openbrush", category: "ble")
    private var vendorService: CBService?
    private var disService: CBService?
    private var tx: CBCharacteristic?
    private var rx: CBCharacteristic?
    private var modelCharacteristic: CBCharacteristic?
    private var softwareCharacteristic: CBCharacteristic?
    private var pendingCharacteristics = Set<CBUUID>()
    private var model: String?
    private var software: String?
    private var gate = OcleanBLERequestGate()
    private var assembler = OcleanTYPE1Assembler()
    private var writeAcknowledged = false
    private var notificationRequested = false
    private var disconnectRequested = false
    private var pendingMessage = ""
    private var pendingSuccess = false
    private var totalTimer: DispatchWorkItem?
    private var scanTimer: DispatchWorkItem?
    private var collectionTimer: DispatchWorkItem?
    private var cleanupTimer: DispatchWorkItem?

    private let serviceUUID = CBUUID(string: OcleanBLEPolicy.service)
    private let txUUID = CBUUID(string: OcleanBLEPolicy.sessionTX)
    private let rxUUID = CBUUID(string: OcleanBLEPolicy.sessionRX)
    private let disUUID = CBUUID(string: "180A")
    private let modelUUID = CBUUID(string: "2A24")
    private let softwareUUID = CBUUID(string: "2A28")

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isBusy, target == nil else {
            if !isBusy { status = "Disconnessione precedente in corso: attendi prima di una nuova acquisizione." }
            return
        }
        attemptID = UUID()
        attemptDeviceKey = "unavailable"; captureIssue = nil
        candidates.removeAll()
        vendorService = nil; disService = nil; tx = nil; rx = nil
        modelCharacteristic = nil; softwareCharacteristic = nil
        model = nil; software = nil; pendingCharacteristics.removeAll()
        gate = OcleanBLERequestGate(); assembler = OcleanTYPE1Assembler()
        writeAcknowledged = false; notificationRequested = false; disconnectRequested = false
        notificationCount = 0; receivedBytes = 0; lastResult = nil; transportCompleted = false
        pendingMessage = ""; pendingSuccess = false
        isBusy = true; phase = .waitingForPower
        status = "Preparazione Bluetooth… Risveglia il display dello spazzolino."
        let token = attemptID
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.attemptID == token else { return }
            self.totalDeadline()
        }
        totalTimer = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + OcleanBLEPolicy.totalSeconds, execute: deadline)
        if let central { processPower(central) }
        else {
            central = CBCentralManager(delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: true])
        }
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isBusy else { return }
        captureIssue = .cancelled
        finish("Acquisizione interrotta. Nessun nuovo tentativo automatico.", success: false)
    }

    private func processPower(_ manager: CBCentralManager) {
        guard isBusy, phase != .cleaning else { return }
        switch manager.state {
        case .poweredOn:
            guard phase == .waitingForPower else { return }
            phase = .scanning
            // Merge both retrieval paths before selecting: two distinct IDs are ambiguous.
            for peripheral in manager.retrieveConnectedPeripherals(withServices: [serviceUUID]) {
                candidates[peripheral.identifier] = peripheral
                logRetrieved(peripheral, source: "collegato-al-sistema")
            }
            if let identifier = knownPeripheral.identifier {
                for peripheral in manager.retrievePeripherals(withIdentifiers: [identifier]) {
                    candidates[peripheral.identifier] = peripheral
                    logRetrieved(peripheral, source: "identificativo-DIS-verificato")
                }
            }
            if !candidates.isEmpty { finishScan(); return }
            status = "Ricerca dello spazzolino vicino…"
            logger.info("Inizio scan foreground senza filtro di servizio; filtro Oclean locale attivo")
            manager.scanForPeripherals(withServices: nil,
                                      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            let token = attemptID
            let timer = DispatchWorkItem { [weak self] in
                guard let self, self.attemptID == token else { return }
                self.finishScan()
            }
            scanTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + OcleanBLEPolicy.scanSeconds, execute: timer)
        case .unknown, .resetting: break // Initial state only; bounded by the total deadline.
        case .poweredOff: finish("Bluetooth spento. Attivalo prima di iniziare una nuova acquisizione.", success: false)
        case .unauthorized: finish("Accesso Bluetooth non autorizzato. Controlla i permessi nelle Impostazioni.", success: false)
        case .unsupported: finish("Bluetooth non supportato su questo dispositivo.", success: false)
        @unknown default: finish("Stato Bluetooth non riconosciuto.", success: false)
        }
    }

    private func finishScan() {
        guard isBusy, phase == .scanning, let central else { return }
        central.stopScan()
        let selection = OcleanDiscoveryPolicy.select(identifiers: Array(candidates.keys))
        guard case .single(let identifier) = selection, let selected = candidates[identifier] else {
            captureIssue = selection == .none ? .scanEmpty : .ambiguous
            logger.info("Discovery conclusa: candidati=\(self.candidates.count, privacy: .public), nessun collegamento")
            finish(OcleanDiscoveryPolicy.failureMessage(captureIssue) ?? "Ricerca non conclusa.", success: false)
            return
        }
        logger.info("Un candidato selezionato; verifica DIS obbligatoria prima della richiesta")
        attemptDeviceKey = SessionHash.deviceKey(peripheralID: selected.identifier)
        target = selected
        selected.delegate = self
        phase = .connecting
        status = "Collegamento allo spazzolino…"
        central.connect(selected, options: nil)
    }

    private func logRetrieved(_ peripheral: CBPeripheral, source: String) {
        // Retrieval reports a known service, NOT an advertisement or a new RSSI measurement.
        logger.info("Periferica recuperata nome=\(peripheral.name ?? "assente", privacy: .private) serviceUUIDAdvertising=non-disponibile RSSI=non-disponibile accettata=true motivo=\(source, privacy: .public)")
    }

    private func one(_ uuid: CBUUID, in service: CBService, property: CBCharacteristicProperties) -> CBCharacteristic? {
        let matches = (service.characteristics ?? []).filter { $0.uuid == uuid }
        guard matches.count == 1, let value = matches.first, value.properties.contains(property) else { return nil }
        return value
    }

    private func resolveCharacteristics() {
        guard pendingCharacteristics.isEmpty, let target, let vendorService, let disService else { return }
        guard let tx = one(txUUID, in: vendorService, property: .write),
              let rx = one(rxUUID, in: vendorService, property: .notify),
              let model = one(modelUUID, in: disService, property: .read),
              let software = one(softwareUUID, in: disService, property: .read) else {
            finish("Caratteristiche mancanti, duplicate o non compatibili. Nessuna richiesta inviata.", success: false)
            return
        }
        self.tx = tx; self.rx = rx
        modelCharacteristic = model; softwareCharacteristic = software
        phase = .identity
        status = "Verifica del modello e della versione…"
        target.readValue(for: model)
        target.readValue(for: software)
    }

    private func disText(_ value: Data?) -> String? {
        guard let value else { return nil }
        var bytes = Array(value)
        while bytes.last == 0 { bytes.removeLast() }
        guard let text = String(bytes: bytes, encoding: .ascii) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func verifyAndSubscribe() {
        guard let model, let software, let target, let rx else { return }
        guard model == "OCLEANY3X", software == "1.0.0.36" else {
            finish(OcleanBLEError.wrongIdentity.localizedDescription, success: false)
            return
        }
        knownPeripheral.remember(target.identifier, model: model, software: software)
        logger.info("DIS verificato: OCLEANY3X, software 1.0.0.36; candidato memorizzato localmente")
        phase = .subscribing
        status = "Modello e versione verificati. Attivazione del canale sessioni…"
        notificationRequested = true
        target.setNotifyValue(true, for: rx)
    }

    private var decoderDeviceKey: String { attemptDeviceKey }

    private func finish(_ message: String, success: Bool) {
        guard isBusy, phase != .cleaning else { return }
        scanTimer?.cancel(); collectionTimer?.cancel(); central?.stopScan()
        if lastResult == nil { lastResult = assembler.result(deviceKey: decoderDeviceKey) }
        if !success && captureIssue == nil { captureIssue = .other }
        pendingMessage = message; pendingSuccess = success; phase = .cleaning
        status = "Chiusura del collegamento…"
        let token = attemptID
        let cleanup = DispatchWorkItem { [weak self] in
            guard let self, self.attemptID == token else { return }
            self.forceDisconnectAndPublish()
        }
        cleanupTimer = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + OcleanBLEPolicy.cleanupSeconds, execute: cleanup)
        if let target, target.state == .connected, notificationRequested, let rx {
            target.setNotifyValue(false, for: rx)
        } else { requestDisconnect() }
    }

    private func requestDisconnect() {
        guard let target else { publishFinish(disconnected: true); return }
        if target.state == .disconnected {
            target.delegate = nil; self.target = nil
            publishFinish(disconnected: true)
        } else if !disconnectRequested {
            disconnectRequested = true
            central?.cancelPeripheralConnection(target)
        }
    }

    private func forceDisconnectAndPublish() {
        requestDisconnect()
        if isBusy { publishFinish(disconnected: target == nil) }
        // Retain target until didDisconnect: a late callback cannot become a new attempt.
    }

    private func publishFinish(disconnected: Bool) {
        guard isBusy else { return }
        totalTimer?.cancel(); scanTimer?.cancel(); collectionTimer?.cancel(); cleanupTimer?.cancel()
        isBusy = false; phase = .idle
        transportCompleted = pendingSuccess && writeAcknowledged
        status = pendingMessage
        if !disconnected { status += " Disconnessione richiesta, conferma non ancora ricevuta." }
        let envelope = OcleanCaptureEnvelope(deviceKey: attemptDeviceKey, capturedAt: Date(),
            result: lastResult ?? .init(status: .incomplete), transportCompleted: transportCompleted,
            issue: captureIssue)
        let completion = captureCompletion; captureCompletion = nil
        completion?(envelope)
    }

    private func totalDeadline() {
        guard isBusy else { return }
        captureIssue = phase == .connecting ? .connectionUnavailable : .timeout
        if phase != .cleaning {
            finish(OcleanDiscoveryPolicy.failureMessage(captureIssue) ?? "Tempo massimo di 75 secondi raggiunto. Nessun nuovo tentativo automatico.", success: false)
        }
        else { pendingSuccess = false; pendingMessage = "Tempo massimo raggiunto durante la chiusura del collegamento." }
        forceDisconnectAndPublish()
    }

    private func finishCollection() {
        guard isBusy, phase == .collecting else { return }
        let result = assembler.result(deviceKey: decoderDeviceKey)
        lastResult = result
        finish("\(result.status.italianDescription). Ricevuti \(result.records.count) record decodificati.", success: true)
    }
}

extension OcleanBLEClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) { processPower(central) }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isBusy, phase == .scanning else { return }
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let hasService = advertisedServices.contains(serviceUUID)
        let match = OcleanDiscoveryPolicy.match(localName: localName, peripheralName: peripheral.name,
            serviceUUIDs: advertisedServices.map(\.uuidString))
        logger.info("Periferica vista nomeAdvertising=\(localName ?? "assente", privacy: .private) nomePeriferica=\(peripheral.name ?? "assente", privacy: .private) serviceUUIDAdvertising=\(hasService, privacy: .public) RSSI=\(RSSI.intValue, privacy: .public) accettata=\(match.accepted, privacy: .public) motivo=\(match.rawValue, privacy: .public)")
        guard match.accepted else { return }
        candidates[peripheral.identifier] = peripheral
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isBusy, phase == .connecting, target === peripheral else { return }
        phase = .services; status = "Ricerca dei servizi richiesti…"
        peripheral.discoverServices([serviceUUID, disUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard target === peripheral else { return }
        if !isBusy { peripheral.delegate = nil; target = nil; return }
        if phase == .cleaning { requestDisconnect() }
        else {
            let ns = error as NSError?
            captureIssue = ns?.domain == CBErrorDomain && ns?.code == CBError.Code.peerRemovedPairingInformation.rawValue
                ? .securityReported : .connectionUnavailable
            finish(OcleanDiscoveryPolicy.failureMessage(.connectionUnavailable)!, success: false)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard target === peripheral else { return }
        peripheral.delegate = nil
        target = nil
        if !isBusy { return }
        if phase != .cleaning {
            pendingMessage = "Collegamento interrotto prima del termine dell'acquisizione."
            pendingSuccess = false; captureIssue = .connectionUnavailable
            lastResult = assembler.result(deviceKey: attemptDeviceKey)
        }
        publishFinish(disconnected: true)
    }
}

extension OcleanBLEClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard isBusy, phase == .services, target === peripheral else { return }
        let services = peripheral.services ?? []
        let vendor = services.filter { $0.uuid == serviceUUID }, dis = services.filter { $0.uuid == disUUID }
        guard error == nil, vendor.count == 1, dis.count == 1 else {
            finish("Servizi richiesti assenti o duplicati. Nessuna richiesta inviata.", success: false); return
        }
        vendorService = vendor[0]; disService = dis[0]
        pendingCharacteristics = [serviceUUID, disUUID]
        phase = .characteristics
        peripheral.discoverCharacteristics([txUUID, rxUUID], for: vendor[0])
        peripheral.discoverCharacteristics([modelUUID, softwareUUID], for: dis[0])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard isBusy, phase == .characteristics, target === peripheral,
              service === vendorService || service === disService else { return }
        guard error == nil else { finish("Ricerca delle caratteristiche non riuscita.", success: false); return }
        pendingCharacteristics.remove(service.uuid)
        resolveCharacteristics()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard isBusy, target === peripheral else { return }
        if phase == .identity {
            if characteristic === modelCharacteristic {
                guard error == nil, let value = disText(characteristic.value), value == "OCLEANY3X" else {
                    finish(OcleanBLEError.wrongIdentity.localizedDescription, success: false); return
                }
                model = value
            } else if characteristic === softwareCharacteristic {
                guard error == nil, let value = disText(characteristic.value), value == "1.0.0.36" else {
                    finish(OcleanBLEError.wrongIdentity.localizedDescription, success: false); return
                }
                software = value
            } else { return }
            verifyAndSubscribe()
            return
        }
        guard characteristic === rx, gate.hasClaimedRequest,
              phase == .awaitingWriteResponse || phase == .collecting else { return }
        guard error == nil, let data = characteristic.value else {
            finish("Errore durante la ricezione delle sessioni.", success: false); return
        }
        guard data.count <= OcleanBLEPolicy.maximumNotificationBytes, assembler.feed(data) else {
            lastResult = .init(status: .limitExceeded)
            finish("Superati i limiti di acquisizione. Lettura interrotta senza nuovi invii.", success: false); return
        }
        notificationCount = assembler.notifications.count
        receivedBytes = assembler.receivedBytes
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard isBusy, target === peripheral, characteristic === rx else { return }
        if phase == .cleaning { requestDisconnect(); return }
        guard phase == .subscribing else { return }
        guard error == nil, characteristic.isNotifying, let tx else {
            finish("Attivazione delle notifiche non riuscita. Nessuna richiesta inviata.", success: false); return
        }
        do {
            let request = try gate.claim(model: model, software: software)
            phase = .awaitingWriteResponse
            status = "Richiesta dello storico inviata una sola volta…"
            logger.info("Invio unico richiesta sessioni 03 07 su fbb89 con risposta")
            peripheral.writeValue(request, for: tx, type: .withResponse)
        } catch { finish("Richiesta non consentita: modello, versione o invio precedente non validi.", success: false) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard isBusy, target === peripheral, characteristic === tx, phase == .awaitingWriteResponse else { return }
        guard error == nil else { finish("La richiesta dello storico non è stata confermata dal collegamento.", success: false); return }
        writeAcknowledged = true; phase = .collecting
        status = "Ricezione dello storico per 12 secondi…"
        let token = attemptID
        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.attemptID == token else { return }
            self.finishCollection()
        }
        collectionTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + OcleanBLEPolicy.collectionSeconds, execute: timer)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard isBusy, target === peripheral, phase != .cleaning else { return }
        finish("I servizi Bluetooth sono cambiati. Acquisizione interrotta senza ripetere la richiesta.", success: false)
    }
}

extension OcleanBLEClient: OcleanCaptureSource {
    @MainActor
    func acquire() async throws -> OcleanCaptureEnvelope {
        guard !isBusy, target == nil, captureCompletion == nil else { throw OpenBrushError.busy }
        return await withCheckedContinuation { continuation in
            captureCompletion = { continuation.resume(returning: $0) }
            start()
        }
    }
}
