# Contratto della sincronizzazione in primo piano

`SyncViewModel` orchestra `OcleanCaptureSource` → `SessionNormalizer` →
`SessionArchivePersistence` → `HealthKitWriter`. Le dipendenze sono sostituibili
nei test. La fonte live è OcleanBLEClient; nessun file Windows è importato.

1. Un tentativo per ingresso in primo piano, oppure tap esplicito. Nessun retry.
2. Discovery: retrieval dei device connessi/già verificati, altrimenti scan foreground
   senza filtro servizio e matching nome Oclean OR servizio. DIS esatto, subscribe fbb90, una sola
   scrittura 03 07 withResponse su fbb89, raccolta 12s, cleanup/disconnect. Restano
   256 notifiche, 8192 byte, timeout totale 75s. Nessun nuovo comando.
3. Cattura con ora iPhone e metadati di trasporto. Un record deve essere comparso
   in almeno una ricezione completa prima di poter essere esportato.
4. Archivio conserva record decodificati, fingerprint e provenienza. Identità e
   namespace esattamente Python; fallback fingerprint per record irrisolti.
   Ingest conserva le varianti e non sottrae sessioni uscite dall'anello.
5. Conversione UTC dall'indice TYPE1 (15 +01,16 +02) e verifica IANA Europe/Rome.
   Gap DST bloccato; fold risolto dall'indice se coerente. Fuso sconosciuto bloccato.
6. Profilo fiducia P0.1 abilita export senza richiedere un riscontro manuale per
   ogni record. Questa è la differenza intenzionale dal gate prudente Python.
   Decoder/assembler e significato di durata restano quelli già documentati.
7. Persistenza atomica PRIMA di qualunque invio HealthKit. Se non riesce, stop.
   File corrotto non viene rimpiazzato con un archivio vuoto. Nessuna rotazione
   automatica. Lo storico resta locale e privato, soggetto ai backup di sistema.
8. Prima dell'invio, stato pending persistito. Writer cerca identità/sovrapposizioni,
   usa ricevute e metadati HK sync. Esito verificato vs accettato non verificato
   distinto. Un arresto può lasciare pending: un nuovo preflight/receipt evita
   una nuova scrittura se l'invio era già riuscito.
9. Variante selezionata con payload differente: syncVersion +1, stessa identità.
   HealthKit gestisce la sostituzione; nessuna chiamata delete dell'app. Una
   versione già visibile superiore non viene retrocessa.
10. Uscita in background cancella la lettura e ferma gli invii successivi. Un
    save già inviato può terminare ed essere registrato, senza rollback fittizio.

Guard rail: anello pieno confrontato col massimo startUTC verificato pre-ingest,
stesso device; warning perdita persistente. Nessun watermark/date invalide:
copertura sconosciuta. Fine oltre prima cattura completa +5s bloccata; oltre120s
anche avviso deriva. Stima indipendente |drift|>120s bloccata. Storico vecchio
da solo NON misura la deriva. Un riferimento dell'utente è archiviato con fonte
e ora di annotazione; non corregge record o clock e non riabilita automaticamente
vecchi record sospetti.

Una nuova identità CoreBluetooth rispetto al device associato resta in hold per
evitare doppia esportazione dopo variazioni d'identità. Non c'è ancora un flusso
di fusione/migrazione tra installazioni o device. TYPE1 non ha id di record: due
eventi fisici con identici byte/tempo/programma non sono distinguibili. Nessuna
deduplica universale fra app diverse senza permesso di lettura.

Le sessioni in hold sono consultabili e la revisione è annotabile. Scegliere una
variante risolve solo l'ambiguità della variante, non un anno invalido o score1.
Esiti HealthKit incerti restano bloccati e richiedono controllo in Salute; non
esiste un pulsante per forzare qualunque dato. L'archivio JSON è privato e non è
un'API di import/export utente in questo incremento.

Test: SessionNormalizerTests (identità, conflitti, hold, DST, clock, ring,
coesistenza, persistenza) e SyncViewModelTests (sette giorni SIMULATI, riavvio,
ricevute, ordine di persistenza, foreground, sovrapposizioni e varianti).
Sono test XCTest preparati per Xcode, non eseguiti su Windows.
