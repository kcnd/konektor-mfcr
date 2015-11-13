# konektor-mfcr
Konektor vytahující data ze smluv zveřejňovaných Ministerstvem financí České republiky a umožňující jejich analýzu

Skript je nutno spustit v adresáři s právem zápisu. Je koncipován tak, aby bylo možné přesměrovat a průběžně sledovat výstup. Data zapisuje do indexu "smlouvy" a typu "mfcr".

K tomuto okamžiku zveřejnilo MFČR 1080 smluv. Většina z nich není strojově čitelná, skript to pozná a poradí si.

Na vzorku dat čítajícím desítky smluv byla úspěšnost převodu dokumentů 100% (nezahrnuje úspěšnost OCR).

Uvnitř skriptu se nenachází žádná human-emerged dokumentace.

# Použití
```
nohup ./konektor-mfcr.sh &
```

# Závislosti
```
# apt-get install poppler-utils tesseract-ocr tesseract-ocr-ces
```

# Adresářová struktura
Skriptem generovaná adresářová struktura:
```
├── contracts // smlouvy tříděné dle ID včetně všech příloh
│   ├── 1000
│   │   ├── 1000564663f3aef2e-ABAX-SoD-pozaruc_srv_VT-2015.pdf
│   │   ├── 1000564663f3aef2e-ABAX-SoD.xlsx
│   │   ├── contract-meta.xml // XML dokument strukturující veškerá data o smlouvě pro možné budoucí strojové zpracování
│   │   └── output.json // JSON dokument uchovaný tak, jak byl odeslán k indexaci
│   └── 1003
│       ├── 1003564663f0c99cf-TranSoft-SoD-Rozvj_eSAT-2015.pdf
│       ├── contract-meta.xml
│       └── output.json
├── contracts_sources // Webové stránky se zdroji smluv a jejich příloh
│   ├── contract_display_1000.html
│   ├── contract_display_1001.html
│   ├── contract_display_1002.html
│   └── contract_display_99.html
├── contract_urls // Seznam webových stránek všech smluv
├── konektor-mfcr.sh
└── list // Stránkované zdroje smluv z katalogu
    ├── 0
    ├── 1
    └── 9
```
