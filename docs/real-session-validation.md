# Validazione di una pulizia reale su OCLEANY3X

2026-11-10: seconda cattura live autorizzata, dopo una pulizia reale completata
con il programma personalizzato abituale. Una sola richiesta 0307, notifiche
fbb90, nessuna conferma 0202, modifica clock, impostazione o firmware.

## Riscontri

Nuovo record: durata prevista 75 s, durata effettiva candidata 75 s, score 59.
Durata e score coincidono con quanto riferito dall'utente. Timestamp del record
coerente con l'orario d'inizio annotato al minuto dall'utente, non con l'ora del
download. scheme_raw=231: identificativo osservato, non un nome programma decodificato.
timezone_raw=15: coerente con l'indice GMT+01:00 della tabella upstream, non ancora
una validazione dei cambi di fuso o ora legale. Nessuna conversione UTC applicata.

Entrambe le catture hanno 32 record: 31 identici byte per byte, uno nuovo e
uno precedente rimosso. Coerente con l'anello a 32 record descritto upstream;
non è uno storico illimitato. Nessun duplicato binario nella cattura attuale.
La seconda richiesta ha ripresentato 31 record senza necessità di conferma:
conservazione osservata, non garanzia universale su ogni firmware/stato.

## Cosa è validato e cosa manca

Prova empirica su questo esemplare/versione: il percorso di download restituisce
un nuovo record coerente con una pulizia reale, inclusi durata e score.
La corrispondenza del timestamp supporta l'interpretazione come inizio, su un
solo evento e con riscontro utente al minuto. L'istante finale non è stato
misurato indipendentemente al secondo; inizio+75s sarebbe un valore derivato.

Un ciclo completo non distingue da solo validDuration da durata programma:
qui entrambe valgono 75. Per validare una pulizia interrotta o con pause servirà
un'altra prova separata, preferibilmente durante il normale utilizzo futuro.
Non occorre una nuova pulizia immediata e nessun'altra cattura è stata avviata.

Restano: deduplica persistente fra catture, gestione record con date anomale,
pause/durata effettiva, fuso/orologio ed esportazione iOS HealthKit.
healthkit_ready resta false, senza estendere la validazione a tutti i record.
Non correggere retroattivamente le date vecchie per ipotesi.

I dati dettagliati e il confronto sono privati in captures/, esclusi da Git;
questa nota omette gli orari personali precisi. Non è stata aperta l'app Oclean
per confrontare lo storico: il motivo del suo zero rimane da confermare.


## Prove A/B preparate — non ancora osservate

Checklist in interrupted-paused-trials.md. Template privati aggiunti sotto
experiments in data/observations.json senza modificare l'osservazione completata.
Nessuna cattura A/B eseguita: non esistono ancora nuovi vettori hardware.
I test di experiments.py sono sintetici, non nuove validazioni del firmware.

| Scenario | Osservato | Decodificato | Stato |
|---|---|---|---|
| A, interruzione ~30s | in attesa del cronometro | nessuna nuova cattura | non eseguito |
| B, pausa ~10s e ripresa | supporto pausa da verificare | nessuna nuova cattura | non eseguito |

La durata di pausa e i byte relativi non sono identificati. Nessun criterio
±2s può essere dichiarato soddisfatto prima di una prova cronometrata reale.
