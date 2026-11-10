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


## Scenario A — prova interrotta, riscontro parziale

Una sola cattura eseguita, nessun retry:57 notifiche/1140 byte, header32 record,
stream incompleto e anomalie di allineamento nella parte successiva. Il decoder
standard mantiene status=incomplete e non restituisce storico completo.
Nel tratto iniziale, un blocco42B plausibile è ancorato a entrambi i record
adiacenti, identici alla baseline: candidato con 75s previsti,30s effettivi,score37.

| Campo | Osservato da Simone | Candidato decodificato | Conclusione |
|---|---|---|---|
| Tempo |30s riferiti alla domanda sul cronometro |30s a9..10 BE |scarto numerico0s, entro±2s del valore riferito |
| Programma |75s abituali,45s restanti sul display |75s a7..8 BE |i due campi differiscono |
| Score |37 |37 a33 |corrisponde |
| Inizio/fine |13:46, entrambi al minuto |inizio candidato13:45:58 |precisione wall-clock insufficiente; non forzare l'orario |
| Integrità |non osservabile manualmente |stream incompleto |riscontro parziale, non promuovere a HealthKit |

Precisione del cronometro non specificata. Il display permette anche di dedurre
75-45=30, ma tale deduzione resta distinta dai30s riferiti sul cronometro.
Questa evidenza supporta la durata effettiva, senza certificare l'intero flusso.
Nessun byte pausa identificato. Scenario B ancora non eseguito e supporto pausa
non accertato. Dettagli privati in data/trial-A-analysis.json; nessun raw personale
aggiunto alle fixture committabili, solo la coppia75/30 in un record sintetico.


## Aggiornamento conclusivo A/B

# Esito prove A/B — interruzione e pausa

## Osservato e decodificato

| Scenario | Osservato da Simone | Prevista BE7..8 | Effettiva BE9..10 | Score grezzo | Risultato |
|---|---|---:|---:|---:|---|
| A, interruzione | cronometro riferito30s;45s rimanenti;score37 |75s |30s |37 |scarto numerico0s rispetto al valore riferito; record successivamente recuperato in stream completo B |
| B, pausa/ripresa | pausa circa5s, stesso ciclo completato; nessun cronometro/orario; display Zone reminder senza score |75s |75s |66 |candidato senza data attendibile; nessun confronto attivo/trascorso entro±2s possibile |

## Dati acquisiti e integrità

Una sola esecuzione capture-sessions per scenario, nessun retry.
A:57 notifiche/1140 byte, header32 record, stream incompleto con anomalie di
allineamento successive al tratto iniziale. Originale conservato come incompleto.
B:68 notifiche/1360 byte, header32, ricomposizione completa con9 byte finali zero.
Il blocco42B del candidato A è identico nella cattura B completa: conferma del
record ricevuta incidentalmente durante B, non una seconda richiesta per A.

Rispetto all'ultima baseline completa precedente ad A, B contiene30 record
identici e due diversi. Uno è A; l'altro è il candidato B, nello slot successivo
che nel prefisso A conteneva ancora un vecchio record. È una associazione per
differenza di memoria, non un timestamp B verificato. Non sommare record diversi.

## Date e punteggi

A: timestamp candidato2026-11-10 13:45:58. Simone ha riferito inizio/fine13:46
al minuto; non forzare il timestamp a13:46:00. Il record30s avrebbe fine derivata
13:46:28. Precisione indipendente del cronometro non specificata; il valore
riferito30s coincide esattamente col campo9..10 e differisce dal programma75s.

B: componenti data [0,1,1,0,12,14], non attendibili nel layout anno+2000.
Non datarlo con l'ora della cattura e non correggere l'anno. Non sappiamo se
il comportamento sia legato alla pausa, a un clock anomalo o a un'altra causa.
Score66 è nei byte, ma il display non mostrava un punteggio: non dire che coincide.
"Zone reminder" resta una osservazione testuale, non un opcode o uno score.

## Osservato, dedotto e non determinabile

- Osservato: coppia75/30 in A e75/75 nel candidato B;score37/66; struttura B completa.
- Riferito dall'utente:30s sul cronometro per A; in B pausa circa5s e ciclo completato,
  senza misure indipendenti di tempo totale, attività o lap.
- Riscontro: A supporta la distinzione tra durata programmata ed effettiva.
- Non determinabile: se B conta o esclude la pausa, durata della pausa nei byte,
  e timestamp reale B. Non trasformare75+5=80 in un tempo realmente misurato.
- Nessuna interpretazione di byte pausa è stata assegnata. Le differenze con il
  record del ciclo completo coinvolgono campi temporali, durata, movimento/zone,
  score e altri byte: una correlazione non prova una funzione pausa.

Con due prove diverse non si può isolare un flag pausa: movimenti e qualità di
pulizia cambiano a loro volta. Gli elenchi di offset variati restano nel report
privato, senza pubblicare valori o raw personali.

## Limiti e Apple Health

A: criterio numerico entro±2s del valore cronometrato riferito soddisfatto (0s),
con precisione dello strumento non documentata e timestamp manuale al minuto.
B: ricostruzione della durata attiva/trascorsa non convalidabile da questa prova;
limite documentato, non risultato positivo. La data anomala è un ulteriore blocco.
Nessuna delle due prove viene promossa automaticamente a evidenza completed-cycle
o a evento HealthKit. L'osservazione originale75s/score59 è rimasta invariata.

## File toccati

- data/observations.json: template completati con ciò che è stato realmente riferito;
- data/trial-A-analysis.json: prima analisi parziale, preservata;
- data/trial-A-complete-record-confirmation.json: riscontro A nello stream completo B;
- data/trial-B-analysis.json: confronto privato e limiti;
- captures/:una nuova cattura A e una B, con derivati del decoder; originali invariati;
- src/openbrushlab/experiments.py: analisi offline e propagazione delle anomalie record;
- tests/test_experiments.py: regressioni solo con durate derivate e restanti campi sintetici;
- docs/interrupted-paused-trials.md: protocollo di prova preparato;
- docs/real-session-validation.md, docs/interrupted-paused-results.md e
  docs/interrupted-paused-validation.txt: risultati e verifiche.

Nessun commit/push/reset/clean. Nessun0202, pairing, clock set, programma,
flash/DFU/OTA o nuovo opcode. Solo0307/fbb89 e subscription/cleanup CCCD fbb90.
Non serve un'altra prova ora; eventuali misure future vanno concordate separatamente.
