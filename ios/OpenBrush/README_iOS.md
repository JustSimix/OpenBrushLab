# OpenBrush iOS â€” sincronizzazione in primo piano

Una sola app SwiftUI + HealthKit + CoreBluetooth, iOS 17+, bundle **it.imix.openbrush**.
Aprire `OpenBrush.xcodeproj`, scheme **OpenBrush**. Nessun importer JSON da Windows.

## Stato verificabile

Sorgenti preparati su Windows il 10 novembre 2026. Controllati sintassi Swift,
collegamenti del progetto e limiti del percorso BLE. **Non compilati con Xcode;
XCTest, radio su iPhone e sette giorni reali NON ancora eseguiti.**
Python resta il banco di prova e la fonte dei vettori sintetici. Le precedenti
schermate P0.1/P0.3 restano nei sorgenti per riferimento, ma la schermata iniziale
ora Ã¨ l'elenco con sincronizzazione e revisione. Nessuna pulizia di prova viene
scritta automaticamente. La fixture pubblica Ã¨ usata nei test.

## Build sul Mac mini

1. Copiare **tutta** questa cartella `ios/OpenBrush` aggiornata al Mac. Non servono
   `.venv`, dati privati, `.device-key`, CocoaPods, XcodeGen o dipendenze Swift esterne.
2. Aprire `OpenBrush.xcodeproj` in Xcode 15+ con SDK iOS 17+. Nel target OpenBrush
   selezionare il proprio Team in Signing & Capabilities, firma automatica e
   capability HealthKit. Conservare `it.imix.openbrush`. Selezionare il Team anche
   per OpenBrushTests per test sul dispositivo. Non Ã¨ incluso un Team ID fittizio.
3. Product > Build, poi Product > Test su un simulatore disponibile. Controllare
   i test di paritÃ  sui 66 vettori, SessionNormalizerTests e SyncViewModelTests.
4. Installare con Run sull'iPhone sbloccato e autorizzato per lo sviluppo.
   Salute, sostituzione per versione e Bluetooth vanno verificati sull'iPhone reale.
5. Il progetto include descrizioni italiane per Salute/Bluetooth. Nessuna capability
   o modalitÃ  di background. L'app deve restare aperta durante la lettura.

Se Ã¨ stata copiata solo questa cartella:

```bash
xcodebuild -list -project OpenBrush.xcodeproj
xcodebuild -project OpenBrush.xcodeproj -scheme OpenBrush \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcrun simctl list devices available
xcodebuild -project OpenBrush.xcodeproj -scheme OpenBrush \
  -destination 'platform=iOS Simulator,id=UUID-REALE-DEL-SIMULATORE' test
```

La build senza firma non installa l'app. Se lavori dalla radice OpenBrushLab,
anteporre `ios/OpenBrush/` al percorso del progetto.

## Uso

Chiudere Oclean, avvicinare lo spazzolino e risvegliare il display. Aprendo l'app
inizia **un tentativo per ingresso in primo piano**, oppure premere **Sincronizza**.
Nessun retry dopo errore. Se lo scan iniziale parte prima che il display sia acceso,
risvegliarlo e usare il pulsante per un nuovo tentativo volontario.

Flusso: scan filtrato â†’ verifica DIS â†’ una richiesta sessioni â†’ decode â†’ archivio
permanente â†’ normalizzazione â†’ Salute. Scan 8s, ricezione 12s, limite totale 75s,
massimo 256 notifiche/8192 byte. In background si interrompe la lettura e non
iniziano altri invii a Salute. Un salvataggio Salute giÃ  in corso puÃ² concludersi.

La sola richiesta vendor Ã¨ `03 07` con risposta su fbb89, notifiche su fbb90.
**Mai `02 02`, clock, programmi, pairing esplicito, DFU o OTA.**

Autorizzare Salute quando richiesto; con permesso negato l'archivio resta sul
telefono. Usare **Autorizza Salute** o Impostazioni per cambiare i permessi.
Il permesso di lettura non Ã¨ deducibile da un risultato vuoto: Â«inviata, verifica
in SaluteÂ» non significa Â«sincronizzata e verificataÂ».

## Archivio e revisione

JSON protetto e scritto atomicamente in Application Support/OpenBrush:
`session-archive-v1.json`. Conserva tutte le sessioni viste, varianti e provenienza,
anche quando escono dall'anello. Ãˆ incluso nei backup di sistema: non Ã¨ una cache.
Nessuna cancellazione o rotazione automatica. Limite 32 MiB: al raggiungimento
si ferma, senza eliminare dati. File assente crea un archivio; file illeggibile o
schema sconosciuto blocca la sincronizzazione senza sostituirlo.
Le ricevute `health-write-receipts-v1.json` sono separate ed escluse dal backup.
Non disinstallare per fare un semplice aggiornamento: la disinstallazione elimina
lo stato locale. Non Ã¨ implementato un ripristino/importazione nell'app.

IdentitÃ  derivata con la stessa regola Python: SHA256 del JSON canonico
`["openbrushlab-session-v1",[device_key,timestamp_locale,indice_tz,programma]]`.
Il device_key iOS Ã¨ un hash con namespace dell'UUID CoreBluetooth locale. Non Ã¨
un MAC nÃ© la chiave privata Python: le identitÃ  Windows/iPhone non coincidono.
Perdita/cambio dell'identitÃ  CoreBluetooth richiede revisione; il nuovo dispositivo
resta in hold. Non si finge un id di record TYPE1. Stesso tempo/fuso/programma ma
record diversi: conflitto, nessuna scelta automatica di durata/score.

Con il profilo P0.1 OCLEANY3X/SW 1.0.0.36 i record completi con data plausibile,
fuso Rome coerente, durata 15..7200s non superiore a quella programmata, score
diverso da 1 e nessun conflitto sono esportabili. Questo Ã¨ un criterio di fiducia,
non una validazione individuale del protocollo di ogni record.
Anno zero, dati invalidi, frammenti, score 1, durate brevi e problemi d'orologio
restano in revisione. Nessuna interpolazione delle date.

Aprire una sessione per **Rivedi**: vedere le varianti, scegliere esplicitamente
quella verificata e rilanciare il controllo. La scelta non scavalca i blocchi su
data/durata/orologio. Una modifica del contenuto esportato aumenta syncVersion
con lo stesso syncIdentifier; non elimina manualmente campioni in Salute.
Un riferimento d'inizio realmente misurato sull'iPhone permette una stima della
deriva senza cambiare i timestamp. I secondi misurati devono essere inseriti esplicitamente:
se non sono stati misurati, non registrare un riferimento. Una buona misura successiva non riabilita
automaticamente vecchie sessioni sospette. I conflitti giÃ  esportati possono
lasciare una versione precedente in Salute: viene segnalato, mai cancellato.

Prima dell'invio si cercano identitÃ  e sovrapposizioni leggibili, anche di altre
sorgenti e di vecchie fixture della stessa app con identitÃ  differente. La
sovrapposizione richiede decisione esplicita per quella sessione, rinnovata dopo
riavvio; non Ã¨ un'autorizzazione globale. Senza lettura Salute non Ã¨ possibile
garantire assenza di eventi Oclean nascosti. Ricevute e metadati sync impediscono
di riscrivere le proprie sessioni giÃ  inviate; non si ricrea automaticamente
un campione che l'utente potrebbe aver eliminato in Salute.

## Avvisi e collaudo

Anello pieno (32): se il record piÃ¹ vecchio Ã¨ successivo all'ultimo sincronizzato
verificato dello stesso dispositivo, avviso di possibile perdita. Senza watermark
o con date invalide, la copertura Ã¨ dichiarata non verificabile. Non si puÃ²
recuperare un record giÃ  sovrascritto. Due pulizie/giorno suggeriscono circa 16
giorni, ma avvii brevi/anomalie possono occupare slot: non Ã¨ una garanzia.

Fine oltre cattura +5s â†’ hold. Deriva stimata assoluta oltre 120s â†’ hold. Record
vecchi non provano una deriva negativa; serve un riferimento indipendente.
Vedi `FOREGROUND_SYNC.md`, `SEVEN_DAY_VALIDATION.md`, `BLE_PROTOCOL_iOS.md` e,
nel progetto completo, `docs/ios-coexistence.md`. Il successo dei sette giorni
resta da misurare, non Ã¨ dimostrato dal test simulato.

Riferimento metadati sync e sostituzione per versione:
https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier
Errore di associazione specifico CoreBluetooth:
https://developer.apple.com/documentation/corebluetooth/cberror-swift.struct/code/peerremovedpairinginformation

## Correzione discovery dopo prova reale iPhone (10 novembre 2026)

La discovery ora recupera prima il device connesso/già verificato; in alternativa
scansiona in foreground accettando nome Oclean OR servizio pubblicizzato.
I vecchi riferimenti a scan solo per servizio sono superati. Il gate DIS è invariato.
Leggere `ios/OpenBrush/DISCOVERY_FIX.md` nel progetto completo, oppure
`DISCOVERY_FIX.md` nella cartella del pacchetto Mac. XCTest: 45 esistenti + 9 nuovi,
da eseguire con Xcode; nessuna prova radio è stata avviata dall'agente.
