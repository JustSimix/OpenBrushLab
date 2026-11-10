# OpenBrushLab

**Aggiornamento iOS:** una sola app nativa in `ios/OpenBrush`, bundle
`it.imix.openbrush`. Python resta banco di prova: nessun trasferimento JSON da
Windows all'app. Vedi [README_iOS.md](README_iOS.md) per build e firma sul Mac mini.
Build/iPhone ancora da verificare. P0.3 aggiunge il client BLE e66 vettori condivisi;
vedi ios/OpenBrush/BLE_PROTOCOL_iOS.md. Nessuna lettura BLE nativa già convalidata.

Documento autonomo per un altro agente: [HANDOFF.md](HANDOFF.md).

Laboratorio Python su Windows per Oclean X Pro Elite Y208, DIS **OCLEANY3X**,
Firmware Revision 1.0 / Software Revision **1.0.0.36**. Non ufficiale.
Niente Flutter, UI, SQLite, server o cloud. Priorità: sessioni -> dati affidabili
-> importazione iOS HealthKit -> altre feature.

## Stato verificato

- Scan, discovery GATT (8 servizi/28 caratteristiche), batteria e revisioni funzionanti.
- Download TYPE1 minimo 0307/fbb89 + notifiche fbb90 verificato su questo esemplare.
- Una pulizia reale completata ha prodotto il record atteso: durata75s, score59,
  orario coerente con l'inizio riferito dall'utente. Nessuna conferma 0202 o reset.
- Archivio JSON e deduplica persistenti, controllo offset/IANA e staging HealthKit
  implementati e applicati alle due catture reali: 64 osservazioni -> 33 voci,
  31 ripetizioni; un candidato iOS e 32 voci trattenute per revisione.
- Nessun evento è stato scritto in Apple Health. Componente iOS, pause e cicli
  interrotti, recupero date anomale, display e impostazioni restano da sviluppare/validare.

Riscontri completi: docs/real-session-validation.md e docs/session-normalization.md.

## Windows / PowerShell

Python3.11+; verificato su Python3.12.10. Ambiente locale .venv già creato.

```powershell
cd E:\Simix\Projects\OpenBrushLab
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m openbrushlab --help
```

Non serve attivare l'ambiente o cambiare ExecutionPolicy. requirements.txt
installa runtime; requirements-dev.txt aggiunge pytest. Dipendenze in pyproject.toml:
Bleak e tzdata (database IANA necessario su Windows). Versioni in
docs/environment-tested.txt. Licenza GPL-3.0-only, attribuzioni MIT conservate.

## Operazioni senza scritture BLE

Chiudere l'app Oclean e risvegliare il display prima dei comandi live; motore spento.

```powershell
python -m openbrushlab scan
python -m openbrushlab gatt --index 1 --scan-seconds 8 --operation-timeout 30 --log logs\gatt-nuovo.jsonl
python -m openbrushlab read --index 1 --scan-seconds 8 --operation-timeout 30 --log logs\read-nuovo.jsonl
```

scan/gatt/read non scrivono caratteristiche o descrittori e non attivano notifiche.
Ogni comando ripete la scansione, gli indici possono cambiare. Con più candidati
usare un indirizzo noto localmente con OPENBRUSHLAB_ADDRESS (o --address).
Per default scan filtra nomi/servizio Oclean; --all aiuta a diagnosticare dispositivi
senza nome. I token cambiano a ogni esecuzione e NON sono identità persistenti.

read legge solo modello/FW/HW/SW/batteria nel servizio standard atteso, non seriale
o SystemID. Duplicati o proprietà mancanti causano skip; stringhe inattese vengono
redatte. Il confronto di versione considera FW e SW ma non certifica il protocollo.

## Cattura con opt-in distinto

```powershell
python -m openbrushlab capture-sessions --index 1 --allow-session-query
```

Questo comando esegue scritture BLE: una richiesta0307 e subscription/cleanup CCCD
su fbb90. Verifica prima modello/versione, rifiuta più candidati se selezionati
per indice, non invia0202, clock set, reset o impostazioni. Nessun retry vendor.
Cattura limitata, dettagli in docs/session-capture.md. Una richiesta di lettura
applicativa trasmessa come write non garantisce effetti nulli su ogni firmware.

## Archivio e preparazione Apple Health, senza Bluetooth

```powershell
python -m openbrushlab normalize-sessions
python -m openbrushlab decode-sessions captures\NOME.raw.jsonl --output captures\NOME-replay.json
python -m openbrushlab decode-status 0303020e74500000
```

L'ultimo payload è sintetico, non una cattura. normalize-sessions importa nuovi
raw, conserva lo storico già acquisito e rigenera data/sessions.json e
data/healthkit-candidates.json. Le osservazioni utente iniziali sono conservate
nell'archivio. --observations consente di sostituirle esplicitamente con un altro
file privato; --timezone sceglie la zona IANA di confronto, predefinita Europe/Rome.

Lo staging JSON è per un futuro importer iOS; Salute non lo importa direttamente.
Include eventi toothbrushingEvent candidati, UTC, identità/versioni sync stabili,
richiesta di revisione ed eventuali ritiri da riconciliare. Date invalide, offset
incoerenti, sessioni brevi/void, conflitti e mancanza di riscontro restano in hold.
Non vengono inventate date o durate e healthkit_ready resta false.
Contratto: docs/healthkit-staging.schema.json; dettagli: docs/session-normalization.md.

## Privacy e integrità

logs/ contiene JSONL redatti: niente indirizzi, nomi, advertisement payload o
eccezioni grezze. UUID, orari di cattura e RSSI restano visibili.
captures/ e data/ sono privati: contengono byte grezzi, orari personali e identità
pseudonime persistenti. Non sono cifrati e NON vanno pubblicati integralmente.
Tutte e tre le directory sono escluse da Git. Fare backup dei dati privati,
dell'archivio e di captures/.device-key per conservarne identità e versioni sync.

I file raw e i log sono creati senza sovrascrittura. L'archivio e lo staging sono
aggiornati separatamente con replace atomico e lock; in caso di staging mancante
rilanciare normalizzazione. Un lock inatteso va esaminato prima di rimuoverlo.
.env.example è documentazione: .env non viene caricato automaticamente.

## Problemi comuni

- count0: svegliare il display e riprovare, evitando scansioni lunghe prima della connessione.
- Timeout: chiudere l'app, risvegliare, usare operation-timeout30. Nei vecchi comandi
  read/gatt la categoria total-timeout può includere anche un timeout di connessione.
- File log già presente: usare un nome nuovo.
- WinRT/STA: terminale PowerShell pulito, senza notebook o librerie GUI/pywin32.
- Versione numerica assente: target_comparison.matches=null; non è incompatibilità provata.
- Zona IANA non disponibile: reinstallare dipendenze per avere tzdata.

Codici: 0 operazione completata (non significa validazione HealthKit), 1 errore,
2 letture parziali o cattura non completa/da rivedere, 130 interruzione.
Git e il remoto configurato dall'utente vengono preservati; nessuna pubblicazione automatica.
Fonti, licenze e inventario: THIRD_PARTY_NOTICES.md, LICENSE, docs/created-files.md.


## App iOS: sincronizzazione in primo piano

L'app nativa ora collega lettura TYPE1, archivio permanente, normalizzazione e
HealthKit. UI italiana con Sincronizza, elenco e revisione delle sessioni.
Leggere [README_iOS.md](README_iOS.md), [contratto iOS](docs/ios-foreground-sync.md)
e [coesistenza con Oclean](docs/ios-coexistence.md).
Sorgenti preparati su Windows: compilazione/XCTest e sette giorni reali sono
ancora da verificare sul Mac mini/iPhone. Nessun invio Bluetooth eseguito da
questo intervento e nessuna pubblicazione Git.
