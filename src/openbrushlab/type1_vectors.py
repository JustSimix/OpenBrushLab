# SPDX-License-Identifier: GPL-3.0-only
"""Public synthetic TYPE1 parity corpus. Never reads captures/ or private data."""
import argparse
import json
from pathlib import Path
from .sessions import decode_frames, MAGIC


def synthetic_record(index=0, *, actual=75, planned=75, date=None, score=42):
    data=bytearray(42)
    data[:6]=bytes(date or (20,2,3,4,5,index%60))
    data[6]=1
    data[7:9]=planned.to_bytes(2,"big")
    data[9:11]=actual.to_bytes(2,"big")
    data[17]=15
    data[33]=score
    return bytes(data)


def stream(records):
    return MAGIC+len(records).to_bytes(2,"big")+b"".join(records)


def split(data,size):
    return [data[i:i+size] for i in range(0,len(data),size)]


def vector_document():
    cases=[]
    public_key="openbrushlab-public-synthetic-key-v1"
    def add(name,frames,description,key=public_key):
        cases.append({"id":name,"description_it":description,"device_key":key,
                      "notifications_hex":[frame.hex() for frame in frames],
                      "expected":decode_frames(frames,key)})
    body=stream([synthetic_record(),synthetic_record(1,actual=30)])
    add("empty",[],"Nessuna notifica")
    add("empty_frame",[b""],"Notifica vuota")
    add("full_complete",[body],"Due record sintetici, durata completa e interrotta")
    add("empty_device_key",[body],"Fingerprint con chiave vuota",key="")
    add("unicode_public_key",[body],"Chiave pubblica UTF-8",key="chiave-di-prova-è")
    for size in (1,2,3,4,5,6,7,13,20,41,49):
        add(f"fragments_{size}",split(body,size),"Header e corpo frammentati, ricomposizione esatta")
    add("empty_frames_without_padding",[b"",body[:3],b"",body[3:]],"Frame vuoti non alterano stream senza padding")
    for count in range(1,11):
        data=stream([synthetic_record(i) for i in range(count)])
        pad=(-len(data))%20
        add(f"zero_padding_count_{count}",split(data+bytes(pad),20),"Padding zero solo nell'ultimo pacchetto da20")
    for count in (32,64):
        data=stream([synthetic_record(i,actual=30 if i==3 else 75) for i in range(count)])
        add(f"ring_{count}",split(data+bytes((-len(data))%20),20),"Anello sintetico e limite massimo64 record")
    add("duplicates",[stream([synthetic_record(),synthetic_record()])],"Record identici conservati e contati")
    add("zero_count",[MAGIC+bytes(2)],"Count zero non implica storico completo")
    add("inline_fragment",[MAGIC+bytes(2)+synthetic_record(actual=30)[:13]],"Frammento inline, senza score o fuso")
    add("inline_header_split",[MAGIC[:2],MAGIC[2:]+bytes(2)+synthetic_record()[:11]],"Inline con header frammentato")
    add("inline_zero_date",[MAGIC+bytes(2)+bytes(13)],"Data tutta zero: nessun record inline")
    add("inline_short",[MAGIC+bytes(2)+synthetic_record()[:10]],"Inline troppo corto")
    add("inline_invalid_date",[MAGIC+bytes(2)+synthetic_record(date=(0,1,1,0,0,0))[:11]],"Inline con anno non attendibile")
    add("inline_extra_bytes_python_contract",[MAGIC+bytes(2)+synthetic_record()[:11]+b"extra"],"Parità: countzero interpreta solo i primi11 byte del frammento")
    for name,date in [('invalid_month',(20,13,1,0,0,0)),('invalid_day',(20,2,30,0,0,0)),
                       ('invalid_hour',(20,1,1,24,0,0)),('invalid_second',(20,1,1,0,0,60)),
                       ('old_year',(14,1,1,0,0,0)),('valid_min_year',(15,1,1,0,0,0)),
                       ('valid_leap',(24,2,29,23,59,59)),('invalid_leap',(23,2,29,0,0,0))]:
        add(name,[stream([synthetic_record(date=date)])],"Validazione gregoriana senza normalizzare date impossibili")
    for actual,planned in ((0,75),(80,75),(7201,7201),(75,0),(7200,7200)):
        add(f"duration_{actual}_{planned}",[stream([synthetic_record(actual=actual,planned=planned)])],"Controlli durata e limiti, senza inventare interpretazioni")
    add("score_255",[stream([synthetic_record(score=255)])],"Score grezzo assente, non convertito")
    add("score_1",[stream([synthetic_record(score=1)])],"Marker score grezzo conservato")
    add("unknown_magic",[bytes(7)],"Header non riconosciuto")
    add("short_header",[MAGIC+b"\x00"],"Header incompleto")
    add("count_65",[MAGIC+bytes([0,65])],"Conteggio oltre64")
    add("count_65535",[MAGIC+bytes([255,255])],"Conteggio malformato massimo")
    add("truncated",[body[:-1]],"Corpo incompleto")
    data=stream([synthetic_record()]);padded=data+bytes((-len(data))%20)
    add("trailing_nonzero",split(padded[:-1]+b"x",20),"Rifiuta coda non zero")
    add("trailing_full_frame",split(padded+bytes(20),20),"Rifiuta un intero frame extra")
    add("padding_variable_frames",[padded[:19],padded[19:]],"Rifiuta padding con dimensioni frame variabili")
    add("padding_empty_frame",[b""]+split(padded,20),"Rifiuta padding se anche un frame non è da20")
    add("padding_single_large_frame",[padded],"Rifiuta padding con notifica singola maggiore di20")
    add("exact_256_frames",[b""]*255+[stream([synthetic_record()])],"Limite esatto256 notifiche")
    add("over_256_frames",[b""]*257,"Rifiuta257 notifiche, anche vuote")
    add("exact_8192_bytes_count_zero",[MAGIC+bytes(8192-5)],"Limite puro8192; il decoder countzero non applica limite512 per frame")
    add("over_8192_bytes",[bytes(8193)],"Rifiuta oltre8192 byte")
    return {"format":"openbrushlab-type1-parity-vectors","schema":1,"privacy":"synthetic-only-no-private-capture-input",
            "oracle":"openbrushlab.sessions.decode_frames","vectors":cases}


def export_vectors(output, *, overwrite=False):
    output=Path(output)
    if output.suffix.lower()!=".json":
        raise ValueError("output must be JSON")
    output.parent.mkdir(parents=True,exist_ok=True)
    document=vector_document()
    with output.open("w" if overwrite else "x",encoding="utf-8") as stream_file:
        json.dump(document,stream_file,indent=2,ensure_ascii=True,sort_keys=True)
        stream_file.write("\n")
    return len(document["vectors"])


def main(argv=None):
    parser=argparse.ArgumentParser(description="Esporta vettori TYPE1 pubblici sintetici, senza Bluetooth")
    parser.add_argument("--output",required=True)
    parser.add_argument("--overwrite",action="store_true")
    args=parser.parse_args(argv)
    try:
        count=export_vectors(args.output,overwrite=args.overwrite)
    except (OSError,ValueError):
        print("Esportazione non riuscita: verifica percorso e sovrascrittura esplicita.")
        return 1
    print(f"Esportati {count} vettori sintetici. Nessuna operazione BLE.")
    return 0


if __name__=="__main__":
    raise SystemExit(main())
