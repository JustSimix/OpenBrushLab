# Normalizzazione, deduplica e staging Apple Health

Tutto offline, Python su Windows, nessuna nuova cattura o operazione BLE.
JSON locale: niente SQLite, UI o Flutter. Dati privati in data/ e captures/,
entrambe escluse da Git. Non sono cifrati dal programma.

## Risultato reale del 10 novembre 2026

Due catture, 64 osservazioni, 33 voci distinte nell'archivio e 31 ripetizioni esatte.
Una candidata per revisione iOS: la pulizia reale verificata con l'utente.
32 voci trattenute: 30 con date non attendibili, due recenti molto brevi.
Le ragioni possono sovrapporsi: tre voci nell'archivio hanno marker score=1
e durata breve, una di queste è anche fra quelle con data non attendibile.
Non chiamare tutte le 33 voci sessioni clinicamente valide.

Il confronto delle ripetizioni è stato eseguito realmente due volte sullo stesso
archivio: secondo import con zero nuove catture, file byte per byte identici,
identificativo e versione di sync invariati. SHA-256 delle catture originali invariati.

## Comando ordinario

```powershell
cd E:\Simix\Projects\OpenBrushLab
.\.venv\Scripts\python.exe -m openbrushlab normalize-sessions
```

Legge solo *.raw.jsonl in captures/, conserva le catture già archiviate, normalizza
e rigenera lo staging. Non serve accendere lo spazzolino. Nessun dato di sessione
o identificativo persistente viene stampato sul terminale: solo conteggi e ragioni.

Output privati:
- data/sessions.json: archivio persistente, provenienza/checksum catture, varianti,
  ID stabili, osservazioni utente e registro versioni degli export;
- data/healthkit-candidates.json: contratto JSON per una futura componente iOS,
  candidati e candidati ritirati da riconciliare, senza scrivere in Salute;
- data/observations.json: riscontro della pulizia riportata dall'utente nella chat,
  associato allo specifico fingerprint: inizio al minuto, ciclo completo 75s, score59.

Il primo import ha usato --observations data/observations.json. Le osservazioni
vengono conservate nell'archivio: omettere il parametro ai successivi import non
le cancella. Passare esplicitamente un altro file sostituisce il set di riscontri;
un file con observations=[] revoca tutti quelli presenti. Non inventare osservazioni
per far passare record anomali. Non modificare le catture per correggere le date.

## Identità e deduplica

Lo spazzolino è distinto tramite device_key pseudonima persistente delle catture,
non tramite i token casuali di scan. I record con data plausibile e formato completo
sono raggruppati per device_key, timestamp locale, indice offset e programma.
Durata e score non fanno parte della chiave: una variazione non deve creare
silenziosamente un nuovo evento da importare.

Ogni gruppo conserva tutti i fingerprint e le catture sorgenti. Record uguali
ricomparsi in un download non creano nuove voci. Varianti binarie diverse nello
stesso gruppo restano conservate ma bloccano l'export per revisione; differenze
di durata/score aggiungono un conflitto esplicito. Non viene scelta automaticamente
la durata maggiore o l'ultima variante. I gruppi con date invalide o frammenti
inline sono distinti solo per fingerprint: nessuna fusione semantica azzardata.

Un anello che sovrascrive vecchi record non li elimina dall'archivio JSON.
L'identità non è infallibile se il dispositivo azzera il clock e riproduce record
identici. Conservare archivio, raw e captures/.device-key: perdere la chiave può
far apparire lo stesso dispositivo come nuovo nelle future catture. Nessuna
deduplica automatica tra app diverse o installazioni senza stato condiviso.

## Date, offset e ora legale

Timezone raw è interpretato con la tabella TYPE1 1-based di dzikus: indice15
= GMT+01:00, indice16 = GMT+02:00, indice0 = sconosciuto. Non sono quarter-hours.
La tabella è una convenzione upstream candidata, riscontrata per l'evento reale;
non viene applicata automaticamente ad altri modelli o firmware per l'export.

Il comando confronta l'offset del record con la zona IANA --timezone, predefinita
Europe/Rome dal contesto dell'utente. tzdata è una dipendenza per rendere questo
controllo disponibile su Windows. Il sistema non usa il fuso corrente del PC
per correggere retroattivamente tutte le sessioni.

La conversione usa prima l'offset registrato e poi verifica il ritorno attraverso
la zona IANA alla data della sessione. Nei cambi autunnali l'offset distingue le
due occorrenze dello stesso orario; un orario inesistente in primavera viene
bloccato. Offset incoerenti, indice sconosciuto, date prima del 2015, data locale
non interpretabile o timestamp futuro rispetto alla cattura restano in revisione.
È controllato anche che una pulizia completata non termini dopo la cattura
(tolleranza 5 secondi). Nessuna sincronizzazione dell'orologio via BLE.

30 record con anno grezzo0 restano senza timestamp normalizzato; si conservano
i sei componenti originali, senza sostituire l'anno con 2026 o ricostruire date
per interpolazione. Un download successivo non rende retroattivamente affidabile
la data di un record vecchio.

## Il candidato verificato

Inizio locale 2026-11-10 11:37:15, indice15: inizio UTC 10:37:15Z.
Durata osservata del ciclo completato 75s: fine derivata 10:38:30Z,
ossia 11:38:30 locale. L'istante finale non è stato misurato al secondo.
Il riscontro utente associa l'ora al minuto, durata e score allo specifico record;
non rende valide tutte le sessioni dello stesso programma.

La fine è esplicitamente derivata da inizio+durata: pause, programma interrotto
e relazione fra tempo motore e intervallo trascorso restano da validare. Non si
esporta automaticamente una durata programmata al posto della durata effettiva.
Per ora vengono candidati solo record con riscontro di ciclo completo, data/fuso
coerenti, trasporto completo, modello/versione previsti e nessun conflitto.

## Contratto con la futura componente iOS

Il JSON non è importabile direttamente nell'app Salute e non è un file XML di
backup Apple. L'app iOS dovrà leggere lo staging, richiedere il permesso HealthKit
e presentare la revisione prima del salvataggio.

Formato openbrushlab-healthkit-staging, schema1, con writes_to_apple_health=false,
requires_review=true e requires_ios_healthkit_authorization=true.
Ogni candidato include:
- type_identifier=HKCategoryTypeIdentifierToothbrushingEvent;
- category_value=notApplicable (simbolo che iOS mapperà alla costante HealthKit);
- start_date/end_date UTC ISO8601 con Z, durata in secondi, zona IANA;
- end_time_is_derived=true e requires_review=true;
- metadata: HKMetadataKeySyncIdentifier stabile, HKMetadataKeySyncVersion intero
  e HKMetadataKeyTimeZone con la zona IANA.

Il registro persistente mantiene versione1 a ogni ripetizione identica. Cambiamenti
materiali del payload o riattivazione dopo ritiro aumentano la versione. Se un
candidato viene bloccato in seguito, retired_candidates ne richiede la
riconciliazione nell'app futura: nessuna cancellazione automatica da Salute.
healthkit_ready resta false nell'archivio. Non sono stati salvati eventi HealthKit.
I metadati sync aiutano le nostre importazioni, non garantiscono l'eliminazione
di eventi già registrati dall'app Oclean o da altre sorgenti.

## Integrità e recupero

Archivio bloccato tramite file .lock esclusivo; lock presente significa processo
in corso o interruzione da esaminare, non viene rimosso automaticamente da altri
processi. Scritture con file temporaneo nello stesso disco, flush/fsync e replace
atomico di ciascun file. Non è una transazione unica fra archivio e staging:
se manca lo staging dopo un errore, rilanciare rigenera lo stesso payload senza
gonfiare le versioni. Le osservazioni restano nell'archivio già salvato.
Archivi non riconosciuti, capture con stesso nome ma checksum diverso e collisioni
tra output/input vengono rifiutati preservando le sorgenti. Fare backup della
cartella privata prima di interventi manuali o migrazioni.

## Fonti

Tabella offset e layout TYPE1: dzikus/esphome-oclean, commit
e74100f042ccb3a01b9cac8acd2a8f5289488466, oclean_protocol.cpp e PROTOCOL.md,
licenza GPL3 conservata. Riscontri reali nei due raw privati e comparison.json.

- https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/toothbrushingevent
- https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier
- https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncversion
- https://developer.apple.com/videos/play/wwdc2020/10184/
