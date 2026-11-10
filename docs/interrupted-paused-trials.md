# Prove reali A/B: interruzione e pausa

Stato: **preparate, non ancora eseguite**. Nessun nuovo record hardware disponibile.
Perimetro: dopo ogni scenario una sola invocazione capture-sessions, coordinata
con Simone. Nessun retry, 0202, pairing, clock, impostazioni, firmware/DFU/OTA.
L'unica richiesta applicativa ammessa è 0307 su fbb89; solo CCCD di fbb90.

## Osservazioni private

Template in data/observations.json, chiave experiments.A / experiments.B.
L'array observations della pulizia da75s è conservato, con backup privato
data/observations.before-interrupted-trials.json. I template non sono osservazioni
verificate per HealthKit: il normalizzatore ignora experiments e mantiene il
precedente riscontro. Mai aggiungere un record interrotto come completed-cycle.

Campi da compilare solo con dati effettivi:
- start_local / pause_start_local / resume_local / final_stop_local: data e ora
  locali, preferibilmente fino al secondo, senza inventare precisione;
- stopwatch_elapsed_s: dall'avvio motore allo stop finale, cronometro continuo;
- stopwatch_pause_s: intervallo misurato a motore fermo, se c'è vera pausa;
- stopwatch_active_s: tempo motore attivo, misurato con lap o derivato da elapsed-pausa,
  registrando il metodo nelle note;
- displayed_score / displayed_duration_s: quanto mostra davvero lo spazzolino,
  null se non mostrato; zero non significa sconosciuto;
- measurement_precision_s: precisione reale dichiarata, non automaticamente2;
- pause_control_supported / motor_restarted_as_new_session / note: comportamento osservato;
- capture_attempts, raw_capture, baseline_capture: tracciabilità del singolo tentativo.

L'agente aggiorna il file dai dati riferiti da Simone. Non deve sovrascrivere
misure mancanti con valori obiettivo. Le ore a mano servono ad associare il record;
la prova ±2s usa il cronometro, non soltanto un orario annotato al minuto.

## Prima di cominciare

1. Chiudere l'app Oclean sul telefono e tenerla chiusa fino alla cattura.
2. Avvicinare lo spazzolino al PC. Lasciare lo stesso programma abituale da75s,
   senza modificare impostazioni o sincronizzare il clock.
3. Predisporre cronometro continuo con lap e annotazioni; registrare l'ora iniziale.
4. Non tenere una connessione BLE aperta durante la pulizia: nessuna cattura parte
   prima che Simone abbia concluso e comunicato le osservazioni.

## Scenario A — interruzione a circa30s

1. Avviare programma e cronometro insieme; annotare l'ora iniziale.
2. Intorno a30s arrestare manualmente la pulizia. Conta il tempo effettivamente
   misurato (es.31.2s), non il valore desiderato30.
3. Fermare il cronometro allo stop del motore; annotare tempo, ora finale,
   durata visualizzata e score, se compaiono. Niente riavvio per leggere il display.
4. Comunicare: «A finita», inizio/stop, cronometro e display. L'agente completa
   il template e marca performed-awaiting-analysis.
5. Quando l'agente dice **«risveglia ora il display»**, risvegliarlo senza motore,
   tenerlo vicino al PC e lasciarlo fermo. L'agente esegue UNA cattura.

L'agente registra capture_attempts=1 prima di invocare il comando, anche se poi
la scansione fallisce; non ripete automaticamente. Conserva risultato e limite.
Un nuovo tentativo richiederebbe rinegoziare esplicitamente questa prova.

## Scenario B — vera pausa di circa10s e ripresa, solo se supportata

Eseguire dopo analisi e cattura A, concordando il momento con Simone.

1. Avviare lo stesso programma75s e il cronometro; annotare inizio.
2. Dopo circa20s di attività usare soltanto il controllo di pausa normalmente
   disponibile sul dispositivo. Nessun tasto/gesto sperimentale o comando BLE.
3. Se non esiste una pausa nota, o lo stop termina la sessione, registrare
   «pausa non supportata/non accertata»: non inventare una procedura.
4. Se il motore entra in pausa, lasciare correre il cronometro e segnare il lap;
   dopo circa10s misurati riprendere con il controllo abituale e segnare il lap.
5. Lasciare completare il ciclo, registrando stop, tempo totale, pausa effettiva,
   durata/display e score. Annotare se la ripresa continua o avvia un nuovo ciclo.
6. Comunicare «B finita» e i dati. Poi, al messaggio «risveglia ora il display»,
   UNA cattura; la baseline B è la cattura A solo se completa, altrimenti l'ultima
   completa con nota esplicita. Non ignorare eventuali due record nuovi.

Se il programma conserva75s di attività, 10s di pausa darebbero circa85s trascorsi:
è un'ipotesi da verificare, non il risultato atteso da forzare nei dati.

## Comando live per l'agente, una sola volta per scenario

```powershell
cd E:\Simix\Projects\OpenBrushLab
.\.venv\Scripts\python.exe -u -m openbrushlab capture-sessions --index 1 --allow-session-query --scan-seconds 15
```

Il comando attuale rifiuta più candidati selezionati per indice; non cambiare
indice per tentativi e non aggirare il controllo. Non inviare richieste aggiuntive
per cercare score/impostazioni. Capture include disattivazione CCCD e disconnessione.

## Analisi offline

experiments.py confronta multinsiemi di record completi fra baseline e nuova
cattura, verificando la stessa identità del dispositivo. Non cambia decoder,
HealthKit o archivio, non contiene BLE. Il report privato può essere salvato così:

```python
import json
from pathlib import Path
from openbrushlab.experiments import analyze_trial
observations = json.loads(Path("data/observations.json").read_text(encoding="utf-8"))
scenario = observations["experiments"]["A"]  # oppure B, solo dopo completamento
report = analyze_trial(scenario["baseline_capture"], scenario["raw_capture"], scenario)
with Path("data/trial-A-analysis.json").open("x", encoding="utf-8") as stream:
    json.dump(report, stream, indent=2)
```

Confrontare 7..8 BE e9..10 BE separatamente. Per A: effettiva<75 e differenza
dal cronometro entro±2s; verificare anche inizio/programma per associare il record.
Un riscontro numerico da solo non conferma l'identità della sessione.
Per B: confrontare durata decodificata sia con attività sia con tempo trascorso.
Se compaiono due record, documentare sessioni spezzate invece di sommarle per
ottenere il risultato voluto. Un eventuale marker pausa non può essere assegnato
solo perché un byte cambia fra due pulizie.

Gli offset variati rispetto alla pulizia completa sono solo un elenco di
correlazioni. Timestamp, durata, score e distribuzioni di movimento cambiano
naturalmente: non sono prove di byte pausa. Senza ulteriori evidenze scrivere
«semantica pausa non identificata» e mantenere healthkit_ready=false.

## Regressioni e privacy

Test sintetici già preparati per durata interrotta e distinzione attività/trascorso.
Dopo i risultati reali aggiungere vettori derivati dalle coppie di durata osservate:
date sintetiche, nessun MAC/device_key/fingerprint, nessun raw completo personale,
campi non necessari azzerati e score sintetico o marker documentato. Dichiarare
che sono vettori sanificati derivati dalla prova, non catture originali.
Conservare raw e report dettagliati solo in captures/ e data/ (ignorati da Git).

## Tabella finale, da riempire solo dopo le prove

| Scenario | Cronometro attivo / trascorso / pausa | Display | BE7..8 | BE9..10 | Scarto | Risultato |
|---|---|---|---|---|---|---|
| A | non misurato | non osservato | non acquisito | non acquisito | n/d | in attesa di Simone |
| B | non misurato | non osservato | non acquisito | non acquisito | n/d | in attesa; verificare supporto pausa |

Aggiornare docs/real-session-validation.md separando osservato, calcolato e
ipotesi. Nessuna promozione automatica dei nuovi esperimenti nell'export HealthKit.
