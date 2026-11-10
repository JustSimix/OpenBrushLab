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
