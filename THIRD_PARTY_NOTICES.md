# Provenienza e licenze

OpenBrushLab 0.1.0 è distribuito sotto GPL-3.0-only, testo integrale in LICENSE.
Non è affiliato a Oclean. Marchi e nomi appartengono ai rispettivi titolari.

## dzikus/esphome-oclean

Fonte: https://github.com/dzikus/esphome-oclean
Commit: e74100f042ccb3a01b9cac8acd2a8f5289488466
Licenza upstream: GNU GPL versione 3 (testo conservato integralmente in LICENSE).
Autori/contributori: dzikus e collaboratori come registrati nel repository upstream;
nessuna attribuzione upstream rimossa dalle copie di ricerca.

Riutilizzo: layout UUID e STATUS da PROTOCOL.md e confronto con
components/oclean/oclean_protocol.cpp e oclean_profile.cpp. Documentazione
parafrasata e decoder STATUS Python scritto per questo laboratorio, con
validazione restrittiva di lunghezza, prefisso, batteria e dock; non è il client
ESPHome. Non sono copiati firmware, immagini, schemi di scrittura o runtime.

## deniskie/ha-oclean-integration

Fonte: https://github.com/deniskie/ha-oclean-integration
Commit: 8b831484c92a02372ee88b1828148ab9552d1007
Licenza: MIT, copyright (c) 2026 Denis Kiesel.
Testo integrale e copyright conservati in third_party/deniskie-MIT.txt.

Riutilizzo: sottoinsieme delle costanti UUID di custom_components/oclean_ble/const.py,
adattato in src/openbrushlab/protocol.py (UUID standard generati da short UUID);
protocol.py e parser.py studiati per comparare profili e limiti, non importati.
Nessuna dipendenza Home Assistant introdotta. Le nostre implementazioni sono nuove;
la distribuzione combinata mantiene la licenza MIT delle parti riutilizzate.

## Copie locali e dipendenze

Copie Git complete shallow in .research/esphome-oclean e
.research/ha-oclean-integration: riferimento locale ignorato dal Git del progetto,
con licenze originali. Non sono un submodule né un remoto di OpenBrushLab.
Per riprodurre lo studio clonare le fonti e fare checkout dei commit indicati.
Bleak, pytest, setuptools e dipendenze transitive restano sotto le rispettive
licenze e non sono vendorizzati; environment-tested.txt registra l'ambiente.
