# P0.3 — decoder TYPE1 condiviso e client BLE iOS

Stato al10 novembre2026: codice e progetto preparati su Windows. Nessuna nuova
operazione BLE, build Apple, firma o prova iPhone eseguita dall'agente.

## Risultati delle verifiche

| Verifica | Stato |
|---|---|
| Suite Python |222 passati |
| Corpus condiviso |66 vettori sintetici,66/66 confronti Python con risultati attesi |
| Core decoder/capture/protocol Python |Invariati, hash confrontati |
| Sintassi Swift |17 file analizzati,0 errori del parser |
| Progetto Xcode |71 oggetti, riferimenti/resource/scheme/plist verificati |
| XCTest totali |21 metodi preparati, NON eseguiti |
| Parità Swift eseguibile |Test pronto sui66 vettori, NON ancora eseguito sul Mac |
| Lettura reale iPhone |NON ancora eseguita |

**Non dichiarare parità nativa100% o collaudo hardware superati finché Simone
non esegue XCTest e la prova sul proprio iPhone.** Il parser sintattico non verifica
tipi/import/linking Apple. Il test XCTest fallisce per qualunque differenza del
risultato strutturato, fingerprint, chiavi mancanti/null o snapshot assembler.

## Un solo corpus, senza dati privati

Esportatore Python: `src/openbrushlab/type1_vectors.py`, eseguibile come modulo.
File canonico condiviso:
`ios/OpenBrush/OpenBrushTests/Fixtures/TYPE1Vectors.json`.
È una risorsa del target **OpenBrushTests**, non dell'app. Python e XCTest leggono
lo stesso file: nessuna copia manuale separata. Non contiene raw personali o chiavi
private e il generatore non legge captures/, data/ o l'ambiente.

```powershell
cd E:\Simix\Projects\OpenBrushLab
.\.venv\Scripts\python.exe -m openbrushlab.type1_vectors --output ios/OpenBrush/OpenBrushTests/Fixtures/TYPE1Vectors.json --overwrite
.\.venv\Scripts\python.exe -m pytest tests/test_type1_vectors.py -q
.\.venv\Scripts\python.exe -m pytest -q
```

Senza --overwrite un file esistente viene rifiutato. Il test rigenera il documento
in memoria e verifica che la risorsa pubblica sia ancora identica; un cambiamento
del decoder Python richiede quindi una rigenerazione deliberata e una revisione
dei risultati, non l'aggiornamento silenzioso delle aspettative Swift.

I66 casi coprono frammentazione header/corpo, padding zero finale a pacchetti20,
anelli32/64, duplicati, countzero/inline, date gregoriane/leap, score grezzi,
durate sospette, magic/count malformati, corpo troncato, coda non zero/frame extra,
dimensioni variabili e limiti esatti/superati256 notifiche e8192 byte.

## Port Swift: stesso risultato del Python

`OcleanTYPE1Decoder.decode` riproduce `sessions.decode_frames` e i record:

- stessi status e campi in snake_case tramite Codable;
- null espliciti per timestamp/score/timezone quando presenti con None nel Python;
- campi opzionali del risultato omessi quando il Python non li emette;
- stesso SHA256 su UTF8(device_key) + NUL + record grezzo;
- stesso controllo gregoriano senza normalizzare giorni impossibili;
- stesse durate BE, score/zone indice grezzi e issues nell'ordine originale;
- stesso padding: da1 a19 byte zero, solo ultima notifica, tutte le notifiche20;
- stesso comportamento countzero: interpreta solo i primi11 byte del frammento
  se sufficienti e non assume storico completo/ultima sessione;
- nessuna conversione UTC o importazione HealthKit nel decoder.

L'assembler conserva al massimo256 notifiche/8192 byte e può produrre lo stesso
snapshot finale. Non blocca prematuramente un header frammentato. Non scarta o
risincronizza byte per tentare di ricostruire una cattura malformata.

Il decoder puro Python non impone512 byte per singola notifica: quel limite
appartiene alla cattura. Anche il port mantiene questa distinzione; il vettore
artificiale con un singolo frame8192/countzero verifica esplicitamente il caso.

## Client CoreBluetooth

`OcleanBLEClient` usa manager e delegate sulla coda principale. Nessuna scansione
o richiesta di permessi parte all'avvio dell'app: solo il tap sulla schermata BLE.
`NSBluetoothAlwaysUsageDescription` in italiano è aggiunta a Info.plist.
Non ci sono background mode, ripristino automatico di connessioni o pairing esplicito.

Sequenza di un singolo tentativo:

1. Prima della scan si uniscono le periferiche già connesse al sistema che espongono
   il servizio e quella recuperabile tramite l'identifier locale già verificato DIS.
   Un candidato viene usato direttamente; più identifier distinti bloccano il collegamento.
2. Se non ci sono candidati recuperati: scan foreground8s senza filtro servizio,
   con accettazione locale per nome advertising/peripheral contenente Oclean
   (case-insensitive) OPPURE servizio Oclean nell'advertising. Gli altri sono scartati.
   Nessun candidato o più candidati: stop. Sempre verifica DIS prima della richiesta.
3. Collegamento all'unico candidato, discovery dei servizi Oclean e DIS180A.
4. Risoluzione per UUID e verifica unicità/proprietà: TXfbb89 write, RXfbb90 notify,
   Model2A24 read e Software2A28 read. Nessun handle hardcoded.
5. Lettura DIS; richiesta vendor bloccata salvo **OCLEANY3X / 1.0.0.36** esatti.
6. Subscribe solo a `5f78df94-798c-46f5-990a-855b673fbb90`.
7. Dopo conferma subscription, gate a invio singolo e unica write
   **03 07** su `5f78df94-798c-46f5-990a-855b673fbb89`, **withResponse**.
8. Raccolta12s dopo risposta della scrittura, accettando anche notifiche arrivate
   fra richiesta e risposta, come fa Python. Prima della richiesta non si decodificano
   notifiche come storico. Nessuna chiusura anticipata solo perché il corpo sembra completo.
9. Limiti256 notifiche,8192 byte complessivi,512 byte per notifica; superamento
   causa stop con errore, non un nuovo download.
10. Unsubscribe solo fbb90 e disconnect. Watchdog totale75s avviato prima della
    preparazione Bluetooth; timeout/cambio servizi/errori/background causano chiusura.

Cleanup ordinario attende fino a3s; il watchdog75s forza la richiesta di
disconnessione senza aggiungere attese oltre il limite locale. CoreBluetooth
completa la disconnessione in modo asincrono: l'app non può promettere il momento
fisico esatto. Se la conferma manca, viene mostrato e un nuovo tentativo è bloccato
finché il vecchio periferico non risulta disconnesso. Timer vecchi sono legati
all'identità del tentativo e non possono interrompere un tentativo successivo.

La riapertura della schermata non avvia retry. Un altro tap, dopo fine e pulizia,
è un nuovo tentativo esplicito dell'utente, non una strategia automatica di retry.

Non ci sono0202, opcode alternativi, orologio, programmi/display, DFU/OTA o
API di cancellazione in Salute. Le sole variazioni CCCD sono subscribe/cleanup
fbb90 gestite da CoreBluetooth. Un eventuale dialogo di sicurezza del sistema
non è un pairing implementato dall'app; non è stato testato su questo firmware.

## Differenze runtime rispetto al banco Python

Non sono differenze intenzionali del formato decodificato: la parità completa
del risultato a parità di input/chiave è il contratto dei66 vettori.
Le seguenti differenze riguardano trasporto e ambiente:

- discovery aggiornata dopo la prova reale iPhone: retrieval prima della scan,
  matching nome Oclean OR servizio come il Python. Il controllo DIS rimane il gate.
  Vedi DISCOVERY_FIX.md per diagnosi e nuova prova. Le note precedenti che
  escludevano matching per nome e retrieval sono superate.
- scan8s e watchdog75s comprensivo del cleanup locale, contro i timeout/configurazioni
  del banco Python. Nessun per-operation timeout30s aggiuntivo nel client iOS;
- Python salva raw privati; iOS mantiene notifiche in memoria, senza log raw o
  trasferimento file, e mostra soltanto i risultati decodificati;
- device_key runtime iOS è locale al periférico CoreBluetooth, derivata dal suo
  UUID locale, non dalla chiave HMAC privata Windows. A input chiave diverso i
  fingerprint differiscono per progetto; timestamp/durate/score/flags restano
  confrontabili. Il test con la stessa chiave pubblica pretende fingerprint identici;
- il dato letto non viene trasformato automaticamente in BrushSession né scritto
  in Salute. La pipeline HealthKit resta separata dalla nuova schermata di lettura.

Non importare `.device-key` da Windows e non confondere i fingerprint runtime
con gli identificativi HealthKit della fixture sintetica. Un'identità persistente
di produzione per BLE/HealthKit è una decisione successiva.

## Build e prova sul Mac mini

1. Copiare l'ultima cartella ios/OpenBrush, inclusa OpenBrushTests/Fixtures.
   Aprire OpenBrush.xcodeproj, scegliere Team, scheme OpenBrush e iPhone iOS17+.
   Mantenere bundle ID **it.imix.openbrush**. Firma come descritto in README_iOS.md.
2. Eseguire prima XCTest, almeno **OcleanTYPE1ParityTests** e **OcleanBLEPolicyTests**.
   Il primo confronta tutti66 casi e l'esatta struttura JSON; il secondo controlla
   gate modello/versione, richiesta unica e costanti di limite. Non apre Bluetooth.
3. Nessun test finito con errore va reinterpretato come parità parziale accettabile.
   Riportare ID del primo vettore fallito oppure il primo errore di compilazione.
4. Sul telefono chiudere l'app ufficiale Oclean, avvicinare e risvegliare lo spazzolino.
   Non avviare il motore. Aprire **Leggi dallo spazzolino**, quindi **Leggi sessioni**.
   Tenere l'app in primo piano. Il codice non invia conferme del registro.
5. Controllare stato, notifiche/byte e record. Se ancora presente nell'anello,
   cercare **2026-11-10T11:37:15**, programma75s, effettiva75s, score59; la data
   mostrata è locale del dispositivo, non conversione UTC certificata.
6. Confrontare con Python sui campi, non col fingerprint calcolato con un'altra chiave.
   Se quel record è stato sovrascritto nell'anello, documentarlo invece di fabbricare
   un dato o inviare altri opcode. Non scambiare la fixture di Salute per il record BLE.
7. Non toccare **Scrivi pulizia di prova** per testare BLE: sono flussi separati.
   Nessun evento BLE viene salvato automaticamente in Salute.

Da terminale Mac, usando un simulatore effettivamente installato per i test:

```bash
xcodebuild -project ios/OpenBrush/OpenBrush.xcodeproj -scheme OpenBrush \
  -destination 'platform=iOS Simulator,id=UUID-DEL-SIMULATORE' \
  -only-testing:OpenBrushTests/OcleanTYPE1ParityTests \
  -only-testing:OpenBrushTests/OcleanBLEPolicyTests test
```

Il simulatore verifica il decoder, non la radio. Per la radio servono iPhone
reale, autorizzazione Bluetooth e spazzolino. Screenshot/output condivisibili
devono escludere identificativi e storico personale non necessario.

## File principali nuovi e modificati

Nuovi:
- src/openbrushlab/type1_vectors.py;
- tests/test_type1_vectors.py;
- ios/OpenBrush/OpenBrush/Protocol/OcleanTYPE1Decoder.swift;
- ios/OpenBrush/OpenBrush/Protocol/OcleanBLEPolicy.swift;
- ios/OpenBrush/OpenBrush/Services/OcleanBLEClient.swift;
- ios/OpenBrush/OpenBrush/Views/OcleanCaptureView.swift;
- ios/OpenBrush/OpenBrushTests/OcleanTYPE1ParityTests.swift;
- ios/OpenBrush/OpenBrushTests/OcleanBLEPolicyTests.swift;
- ios/OpenBrush/OpenBrushTests/Fixtures/TYPE1Vectors.json;
- ios/OpenBrush/BLE_PROTOCOL_iOS.md e VALIDATION_P03.md.

Modificati: progetto Xcode (sorgenti/framework/resource test), Info.plist,
ContentView (accesso alla schermata BLE), README_iOS e nota di stato nel README.
I precedenti writer/modello/fixture HealthKit e i core Python di cattura/decoder
non sono modificati. Nessun commit/push/reset/clean e nessun dato privato nel corpus.

## Fonti

Oracolo: sessions.py locale, protocollo e cattura documentati in docs/protocol.md
e docs/session-capture.md. Attribuzioni GPL/MIT del repository conservate.
- https://developer.apple.com/documentation/corebluetooth/
- https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/PerformingCommonCentralRoleTasks.html
- https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription
