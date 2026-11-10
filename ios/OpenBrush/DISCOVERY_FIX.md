# Correzione discovery iPhone — istruzioni per Chief e Simix

Modifica mirata del 10 novembre 2026, senza UI/layout, HealthSync o background.

## Comportamento

Prima dello scan vengono uniti per UUID locale i candidati restituiti da
retrieveConnectedPeripherals(withServices: [servizio Oclean]) e
retrievePeripherals(withIdentifiers: [identifier salvato]). L'identifier viene
memorizzato nelle preferenze private dell'app solo dopo connessione e DIS esatto
OCLEANY3X / Software Revision 1.0.0.36. Nessuna memorizzazione da advertising.
Ogni nuovo collegamento, anche dal cache, verifica nuovamente il DIS.
Un solo UUID → tentativo diretto; più UUID → ambiguous, nessun collegamento.
Nessun tentativo su un secondo candidato se il primo fallisce.

Se retrieval non trova candidati: scan con withServices:nil per gli stessi8s
di OcleanBLEPolicy.scanSeconds. Accetta se uno dei due nomi contiene Oclean,
case-insensitive, OPPURE se l'advertising pubblicizza il servizio Oclean.
Gli altri dispositivi sono registrati come scartati e non vengono collegati.
La selezione resta determinata a fine scan: mai il primo device visto arbitrariamente.

Restano gate DIS, UUID delle caratteristiche, una richiesta03 07 con risposta,
subscribe/unsubscribe fbb90, 12s raccolta, 256 notifiche, 8192 byte, watchdog75s.
Nessun opcode alternativo, retry vendor, pairing esplicito o cancellazione Salute.
Un identifier in cache non garantisce che lo spazzolino sia acceso/raggiungibile:
se non si collega, si ferma al timeout e occorre un nuovo tap volontario.

## Messaggi e log

Messaggi distinti per nessun Oclean visto, più dispositivi e Oclean trovato ma
collegamento fallito/timeout. Nell'ultimo caso si invita a chiudere Oclean e altri
collegamenti: «potrebbe essere già collegato a un'altra app». Non è una diagnosi
certa; iOS non rivela l'app proprietaria del collegamento né il motivo di un
mancato advertising. Se non si vede nulla e non c'è cache, un device occupato
non è distinguibile da uno spento/lontano. Retrieval di un device connesso al
sistema non prova che Oclean sia aperta: occorre comunque connect locale.
Il messaggio finale BLE ora arriva al testo di stato dell'app, senza essere
sostituito da quello generico. Mojibake corretto solo nei sorgenti toccati.

Logger: subsystem it.imix.openbrush, category ble. Console del Mac o console
Xcode, app collegata all'iPhone. Per ogni advertising: entrambi i nomi (privacy
private), flag servizio pubblicizzato, RSSI, accettazione e motivo. I nomi possono
apparire come <private> nelle esportazioni di sistema; non disabilitiamo la
redazione. Per i device recuperati RSSI e advertising sono «non-disponibile»:
non vengono inventati. Nessun indirizzo, identifier periferica, device_key o
payload viene aggiunto ai log o ai JSON esportati. La preferenza privata contiene
il solo identifier locale necessario a retrievePeripherals, mai incluso nello ZIP.
PrivacyInfo dichiara UserDefaults per dati accessibili solo a questa app (CA92.1).

## Chief — Mac mini

1. Estrarre la cartella OpenBrush dal nuovo ZIP in una destinazione separata e
   aprire OpenBrush.xcodeproj. Sono i sorgenti completi, nella stessa forma del
   pacchetto precedente. Nessun dato captures/data/logs o .device-key incluso.
2. Team e firma come prima, bundle it.imix.openbrush invariato. Product > Build
   e Product > Test. Attesi **54 test XCTest: 45 esistenti + 9 nuovi**; il test
   di parità continua a caricare66 vettori. Su Windows solo sintassi/struttura,
   nessuna compilazione SDK Apple e nessun XCTest eseguito.
3. Installare sopra l'app esistente, senza disinstallare o cancellare lo stato.
   Conservare archivio e ricevute. Build/installazione sono di Chief.

## Simix — prova reale

1. Chiudere Oclean e altre letture Python/Bluetooth. Avvicinare e risvegliare il
   display dello spazzolino. Non serve avviare una nuova pulizia.
2. Lasciare OpenBrush in primo piano e premere Sincronizza se l'apertura non ha
   già avviato un tentativo. Non premere ripetutamente mentre sta lavorando.
3. Atteso al primo tentativo senza cache: nome Oclean accettato anche SENZA
   servizio nell'advertising → un candidato → DIS OK → singola03 07 su fbb89
   → raccolta12s → unsubscribe/disconnect → decode come prima.
4. Dopo DIS verificato e nuova sincronizzazione, può apparire la via retrieval
   senza scan; DIS viene sempre ricontrollato e03 07 resta una sola per tentativo.
5. Annotare messaggio preciso e log categoria ble (motivo accettazione/scarto,
   candidati, DIS verificato, invio unico). Se fallisce riportare la fase e l'esito,
   senza chiavi private o identificativi. Nessun reset o pairing forzato.
6. Se ci sono due Oclean realmente distinti, atteso ambiguous e zero connect
   nella fase retrieval o scan che li ha osservati. Non viene garantito di trovare
   un secondo device non annunciato quando è già stato recuperato un candidato:
   come richiesto, un candidato recuperato viene usato senza un ulteriore scan.

## Riferimenti Apple

- [Scan e parametro nil](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:))
- [Periferiche connesse al sistema](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:))
- [Periferiche note per identifier](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveperipherals(withidentifiers:))
- [UserDefaults e motivazione CA92.1](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
