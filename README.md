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
