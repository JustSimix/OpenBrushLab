# OpenBrushLab: fattibilità e priorità P0

Analisi 2026-11-10 su OCLEANY3X, Y208 dichiarato dall'utente.
DIS letto realmente: Firmware Revision=1.0, Software Revision=1.0.0.36.
Priorità: recuperare timestamp e durata effettiva, poi Apple Health.
Nessuna nuova operazione BLE eseguita per questa analisi.

## Risultato

Il P0 ha una base tecnica concreta, ma non abbiamo ancora letto una sessione.
Le caratteristiche del protocollo TYPE1 sono presenti; ciò dimostra la topologia
del trasporto, non il contenuto della memoria o la compatibilità del parser.
Storico vuoto nell'app non dimostra memoria vuota sullo spazzolino.

## Evidenze locali

Inventario: logs/gatt-agent-20261110-094441.jsonl, 8 servizi, 28 caratteristiche.
Letture standard ripetute con successo, batteria 83%. Il filtro hardware
rimane attivo; nessuna revisione nascosta viene interpretata per deduzione.

Nel servizio 8082caa8-41a6-4021-91c6-56f9b954cc18:

| UUID, suffisso | Handle caratteristica | Proprietà osservate | Ruolo upstream |
|---|---:|---|---|
| 9d84b9a3-000c-49d8-9183-855b673fbb85 | 20 | read/write | TX principale |
| 5f78df94-798c-46f5-990a-855b673fbb86 | 22 | read/notify, CCCD 24 | risposte stato/impostazioni |
| 5f78df94-798c-46f5-990a-855b673fbb87 | 25 | read/write | non attribuito in questa analisi |
| 5f78df94-798c-46f5-990a-855b673fbb88 | 27 | read/notify | non attribuito in questa analisi |
| 5f78df94-798c-46f5-990a-855b673fbb89 | 29 | read/write | TX richiesta storico |
| 5f78df94-798c-46f5-990a-855b673fbb90 | 31 | read/notify, CCCD 33 | RX record storico |

Gli handle sono quelli della cattura, non offset del valore ATT da usare a mano;
un futuro client deve risolvere le caratteristiche correnti, senza hardcoding.
Il servizio FEF5 con ulteriori 10 caratteristiche non è stato identificato con
certezza dai riferimenti esaminati: non viene chiamato canale display o OTA
senza prove. Proprietà read/write non descrivono il significato applicativo.

## Perché lo storico richiede un cambiamento del vincolo BLE

Il percorso TYPE1 documentato scrive 03 07 su fbb89 e riceve su fbb90.
Attivare le notifiche può scrivere il CCCD. La proprietà read sulle medesime
caratteristiche non garantisce uno storico leggibile senza richiedere il download.
Le letture standard attuali non interrogano la memoria delle sessioni.

Non ho attivato questo percorso: l'istruzione nessuna scrittura resta valida.
Neppure il polling degli upstream è stato importato o eseguito. 02 02 conferma
le sessioni e può farle smettere di essere offerte; deve restare escluso.
Una richiesta di lettura applicativa trasmessa come write non equivale a un
reset, ma i suoi effetti su questo firmware vanno comunque verificati.

## Formato candidato per P0

dzikus documenta intestazione 03 07 2A 42 23 + count BE, poi record di 42 byte.
Il decoder C++ usa data/ora del dispositivo a offset 0..5, programma a 6,
durata programma BE a 7..8, durata effettiva BE a 9..10, timezone a 17.
Per Apple Health ci interessa la durata effettiva: un programma da 120 secondi
interrotto a 70 non deve diventare una sessione da 120.

Limiti da risolvere prima di esportare:
- validare questa struttura sullo Y3X; record troncati o altri formati vanno
  conservati come sconosciuti, non forzati nel layout;
- ricomporre notifiche frammentate, controllare dimensioni, count e date;
- il timestamp dipende dal clock dello spazzolino: verificare offset, ora legale,
  e se indica inizio/fine prima di costruire gli intervalli HealthKit;
- una risposta count=0 può contenere un frammento vecchio, non una cronologia
  completa né la prova che non si sia mai spazzolato;
- dzikus descrive un anello di 32 record su dispositivi verificati: non promettere
  mesi/anni di recupero o 32 record sullo Y3X prima di misurarlo;
- distinguere durata motore attivo, pause ed effettivo intervallo trascorso:
  un record aggregato potrebbe non ricostruire ogni pausa.

## Esperimento proposto, non implementato né eseguito

1. Prima acquisire lo storico esistente, senza richiedere una nuova spazzolata.
2. In una futura modalità separata, con autorizzazione esplicita: sola richiesta
   vendor 03 07 su fbb89 con risposta, subscription fbb90, raccolta limitata e
   disconnessione. Nessuna conferma 02 02, cambio ora, reset, programma o firmware.
   Se il percorso minimo non risponde, fermarsi: niente tentativi automatici
   di opcode o richieste aggiuntive.
3. Salvare subito la cattura localmente come dato sensibile, senza pubblicarla.
   I log pubblicabili attuali non devono essere riutilizzati per riversare byte
   sconosciuti senza redazione; timestamp e abitudini di pulizia sono privati.
4. Decodificare offline. Ripetere download senza conferma e verificare stabilità
   e deduplica. Se lo stato del dispositivo cambia, registrarlo e fermare i test.
5. Solo dopo la cattura iniziale fare una normale pulizia reale, preferibilmente
   un ciclo completo del programma abituale. Annotare inizio, fine, pause e durata
   visualizzata; nessuna istruzione medica o modifica della routine richiesta.
   Non usare un impulso di pochi secondi come test principale: upstream descrive
   sessioni <=14 secondi o quasi senza movimento come invalidabili. Y3X da verificare.
6. Scaricare di nuovo e cercare un record coerente con quella pulizia. Un successivo
   test interrotto può distinguere durata effettiva da durata impostata; non serve
   farlo ora e non occorre tenere il motore acceso per discovery/connessione.

Criterio P0 Python: almeno un record reale con data/ora verificabile e durata
effettiva coerente, secondo download senza duplicati, cattura originale conservata,
nessuna conferma o reset. Se c'è solo un frammento inline, dichiarare il limite.

## Apple Health, dopo il criterio Python

Apple espone toothbrushingEvent come campione di categoria, valore notApplicable,
con intervallo temporale. La piccola componente iOS richiederà il permesso per
scrivere questi eventi. Nessun export JSON su Windows scrive direttamente nel
database Salute dell'iPhone; nessuna app iOS o Flutter viene sviluppata ora.

Flusso previsto: cattura locale -> parser -> archivio JSON con identità stabile
locale dello spazzolino e sessione -> importazione iOS -> HealthKit. I token
casuali dei log di scansione cambiano a ogni esecuzione e NON sono ID di sessione.
La deduplica deve persistere tra esecuzioni e tra invii Windows/iOS, senza basarsi
solo sulla data di download. I payload uguali aiutano il riscontro, ma gli ID
devono sopravvivere anche all'arricchimento di un record incompleto.

HKMetadataKeySyncIdentifier e HKMetadataKeySyncVersion supportano aggiornamento
e sincronizzazione. Serve comunque un registro delle nostre importazioni e una
politica per eventi già creati da Oclean/altre fonti: nessuna promessa che Apple
elimini da sola tutti i duplicati tra app. Niente import di date invalide o
correzione silenziosa del clock. Prima validare, poi decidere come correggere.

## Fattibilità delle dieci priorità

| Priorità / funzione | Valutazione attuale |
|---|---|
| P0 storico data/ora/durata | Miglior candidato prossimo: canali presenti, dati non ancora richiesti |
| P0 Apple Health | Tipo HealthKit disponibile; dipende dai record Python verificati |
| P1 qualità, score/zone | Campi upstream candidati; non chiamare zone pressione calibrata, interpretazioni da validare |
| P1 dashboard/gamification | Derivabili da record validati; rinviate, nessuna UI avviata |
| P2 programmi | Encoding upstream disponibile, scritture e verifica richieste; rinviato |
| P2 display | Lingua/tema non provano testo/immagini; rendering arbitrario non dimostrato |
| P3 telemetria live | Bassa evidenza: upstream descrive sessioni bufferizzate, non uno stream durante la pulizia |
| P3 batteria/manutenzione | Batteria già letta; autonomia da serie temporali, usura stimata da utilizzo, non misura fisica |
| P3 Home Assistant | Percorso upstream esiste; eventi dopo download, dipende da P0 sullo Y3X |
| P3 easter egg/giochi | Speculativo, subordinato alla scoperta di un vero canale display |

## Diagnosi app ufficiale

Ipotesi separabili: record presenti ma app non li importa/mostra; clock/date
invalide; sessioni brevissime invalidate; coda già confermata; memoria senza
record nuovi; formato non riconosciuto. Per ora non è possibile attribuire la
causa ad app, cloud o firmware. Cattura prima/dopo pulizia è il test discriminante.
Non suggeriamo factory reset, aggiornamenti o sincronizzazione dell'orologio
prima di salvare le evidenze esistenti.

## Fonti e provenienza

- dzikus, commit e74100f042ccb3a01b9cac8acd2a8f5289488466, PROTOCOL.md,
  oclean_protocol.{h,cpp}, oclean_profile.cpp e README (GPL v3, copie .research).
  https://github.com/dzikus/esphome-oclean/blob/main/PROTOCOL.md
- deniskie, commit 8b831484c92a02372ee88b1828148ab9552d1007, protocol.py,
  parser.py e docs/BLE-PROTOCOL-REFERENCE.md (MIT, copie .research).
  OCLEANY3X -> TYPE1 è un mapping di famiglia con supporto parziale:
  https://github.com/deniskie/ha-oclean-integration/pull/145
- https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/toothbrushingevent
- https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier
- https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncversion

Questa analisi non modifica codice BLE, non crea interfacce e non pubblica dati.


## Aggiornamento implementazione

Cattura minima e decoder candidato preparati dopo questa analisi: 92 test offline passati; nessuna cattura live eseguita. La descrizione dell'esperimento sopra e la proposta originaria; stato e istruzioni correnti in session-capture.md.
