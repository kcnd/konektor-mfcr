#!/bin/bash

# Závislosti:
# sudo apt-get install poppler-utils tesseract-ocr tesseract-ocr-ces

# Na konec tohoto URL přijde číslo se stránkou
BASE_URL='https://mfcr.ezak.cz/index.php?m=contract&a=index&type=all&state=all&archive=ALL&page='

# Z jakých stránek se mají smlouvy stahovat
RANGE_FROM=0
RANGE_TO=71

XML_META_FILENAME="contract-meta.xml"
JSON_FILENAME="output.json"

FAILED_TO_INDEX_FILENAME="failed_to_index.log"

OCR_TEMP_DIR=/tmp/contracts-to-images # Za účelem použití v OCR

mkdir -p list
mkdir -p contracts_sources
mkdir -p contracts
mkdir -p $OCR_TEMP_DIR

function kcnd_json_escape {
    echo -e "$1" \
      | sed 's/\\/\\\\/g' \
      | sed 's/"/\\"/g' \
      | sed ':a;N;$!ba;s/\n/\\n/g' \
      | sed 's/\x09/\\t/g' \
      | sed 's/\//\/\//g' \
      | sed 's/\x08/\\b/g' \
      | sed 's/\x0C/\\f/g' \
      | sed 's/\x0D/\\r/g'
}

# Stažení stránek z katalogu smluv
for ((PAGE=$RANGE_FROM; $PAGE <= $RANGE_TO; PAGE++))
do
	echo "Stahuji stránku ${PAGE} z $RANGE_TO"

	PAGE_URL=${BASE_URL}${PAGE}
			
	curl --silent "$PAGE_URL" > list/${PAGE}
done

# Nalezení smluv ve stránce
touch contract_urls
for ((PAGE=$RANGE_FROM; PAGE <= $RANGE_TO; PAGE++))
do
	echo "Zjišťuji URL smluv ze stránky ${PAGE} z ${RANGE_TO}"

	grep -oP 'contract_display_(\d+)\.html' list/${PAGE} >> contract_urls
done

BASE_URL='https://mfcr.ezak.cz/'
NUM_OF_CONTRACTS=$(cat contract_urls | wc -l)

echo "Nalezl jsem ${NUM_OF_CONTRACTS} smluv"

# Stažení jednotlivých stránek se smlouvami
while read CURR_CONTRACT_ID;
do
	echo "Stahuji smlouvu ${CURR_CONTRACT_ID}"

	CONTRACT_URL=${BASE_URL}${CURR_CONTRACT_ID}
	
	curl --silent "$CONTRACT_URL" > contracts_sources/${CURR_CONTRACT_ID}

done < ./contract_urls



# ==== Analýza smluv a jejich dokumentů ====


## Tika server
echo "Startuji Apache Tika..."
TIKA_PID=$(java -jar tika-server-1.11.jar > /dev/null 2>&1 & echo $!)
sleep 5
echo "Hotovo, server Tika běží pod PID $TIKA_PID"

cd contracts_sources

echo '' > /tmp/contract_parts

for CURR_CONTRACT_SOURCE_FILE in ./*
do
    
    CURR_CONTRACT_ID=$(echo $CURR_CONTRACT_SOURCE_FILE | grep -oP '(?<=contract_display_)[0-9]+(?=\.html)')
	echo -n '' > /tmp/contract_parts

	cat $CURR_CONTRACT_SOURCE_FILE | grep -oP '(?<=href=")document_[0-9]+/.+\.[a-z0-9A-Z]{3,5}(?=" title)' >> /tmp/contract_parts

    CONTRACT_SUBJECT=$(cat $CURR_CONTRACT_SOURCE_FILE | grep -ozPa '(?<=Veřejná zakázka: ).+(?=\n)')
    PUBLIC_ID=$(cat $CURR_CONTRACT_SOURCE_FILE | grep -ozPa '(?<=\nSystémové číslo VZ: <b>)[A-Z0-9]+(?=</b>)')
    TYPE_OF_CONTRACT=$(cat $CURR_CONTRACT_SOURCE_FILE | grep -oPa '(?<=<li>Druh veřejné zakázky: <b>).+(?=</b></li>)')
    WORKING_DIR="../contracts/${CURR_CONTRACT_ID}"
    mkdir -p $WORKING_DIR
    cd $WORKING_DIR

    # XML
    touch $XML_META_FILENAME
    echo '<?xml version="1.0" encoding="UTF-8" ?>' >> $XML_META_FILENAME
    echo '<smlouva xmlns="https://es.vse.cz/smlouvy/mfcr">' >> $XML_META_FILENAME
    echo "  <predmet>${CONTRACT_SUBJECT}</predmet>" >> $XML_META_FILENAME
    echo "  <url>${BASE_URL}${CURR_CONTRACT_SOURCE_FILE}</url>" >> $XML_META_FILENAME
    echo "  <id_smlouvy_z_url>${CURR_CONTRACT_ID}</id_smlouvy_z_url>" >> $XML_META_FILENAME
    echo "  <id_verejne_zakazky>${PUBLIC_ID}</id_verejne_zakazky>" >> $XML_META_FILENAME
    echo "  <druh>${TYPE_OF_CONTRACT}</druh>" >> $XML_META_FILENAME
    echo '  <dokumenty>' >> $XML_META_FILENAME

    # JSON - mohl jsem použít nějaký nástroj který převádí XML do JSON automaticky, ale výsledek je nevalný
    CONTRACT_SUBJECT_JSON=$(kcnd_json_escape "${CONTRACT_SUBJECT}")

    touch $JSON_FILENAME
    echo -n "{" >> $JSON_FILENAME
    echo -n "\"predmet\":\"${CONTRACT_SUBJECT_JSON}\"," >> $JSON_FILENAME
    echo -n "\"url\":\"${BASE_URL}${CURR_CONTRACT_SOURCE_FILE}\"," >> $JSON_FILENAME
    echo -n "\"id_smlouvy_z_url\":\"${CURR_CONTRACT_ID}\"," >> $JSON_FILENAME
    echo -n "\"id_verejne_zakazky\":\"${PUBLIC_ID}\"," >> $JSON_FILENAME
    echo -n "\"druh\":\"${TYPE_OF_CONTRACT}\"," >> $JSON_FILENAME
    echo -n "\"dokumenty\":[" >> $JSON_FILENAME

    # Indikátor prvního dokumentu kvůli čárce mezi jednotlivými objekty v poli dokumentů
    FIRST_DOCUMENT=true

	while read DOCUMENT_PATH; do
		DOCUMENT_URL=${BASE_URL}${DOCUMENT_PATH}
        DOCUMENT_ENCODED_NAME=$(echo "${DOCUMENT_PATH}" | grep -oP '(?<=/).+')
        DOCUMENT_NAME=$(python -c "import sys, urllib as ul; print ul.unquote_plus(sys.argv[1])" "${DOCUMENT_ENCODED_NAME}")
        DOCUMENT_FILE_TYPE=$(echo -e "${DOCUMENT_NAME}" | grep -oP '(?<=\.)[a-zA-Z]{3,5}' | tr -d '\n')

        echo -n "Smlouva (${CURR_CONTRACT_ID}) dokument (${DOCUMENT_NAME}) ... stahuji ..."

		curl --silent "$DOCUMENT_URL" > "${DOCUMENT_NAME}"

        DOCUMENT_MD5=$(md5sum "${DOCUMENT_NAME}" | sed 's/ .*//g')

        echo -n " OK ... zjišťuji obsah ... "

        #TODO vytáhnout obsah
        DOCUMENT_RAW_TEXT=$(curl --silent http://localhost:9998/tika --header "Accept: text/plain" -T "${DOCUMENT_NAME}")

        if [[ -z "${DOCUMENT_RAW_TEXT// }" ]]; then
            # Tohle je strojově nečitelné, je třeba na to spustit OCR
            # OCR neumí pracovat přímo s pdf, takže je třeba pdf konvertovat do obrázků
            pdfimages "${DOCUMENT_NAME}" ${OCR_TEMP_DIR}/image

            ITERATOR=0
            FILE_COUNT=$(ls -1 ${OCR_TEMP_DIR} | wc -l)

            echo -e -n "\nDokument není strojově čitelný, spouštím OCR...\nCelkem stránek: ${FILE_COUNT}\nRozpoznávám text na stránce"

            # Rozpoznání textu z obrázků
            for IMAGE_FILENAME in ${OCR_TEMP_DIR}/*
            do
                echo -n " $((++ITERATOR))"
                tesseract -l ces "${IMAGE_FILENAME}" /tmp/OCR_output > /dev/null 2>> /dev/null
                DOCUMENT_RAW_TEXT+=$(cat /tmp/OCR_output.txt)
                echo -n '' > /tmp/OCR_output.txt
            done

            # Vyčištění dočasné složky pro další použití
            rm -f ${OCR_TEMP_DIR}/* 

        fi

        # Text je třeba před uložením do XML ošetřit
        DOCUMENT_TEXT_XML=$(echo "${DOCUMENT_RAW_TEXT}" | sed 's/&/\&amp;/g' | sed "s/'/\&apos;/g" | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g' | sed 's/"/\&quot;/g')
        #DOCUMENT_TEXT_JSON=$(echo -e "${DOCUMENT_RAW_TEXT}" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/\x09/\\t/g')

        echo " OK"

        # XML
        echo "      <dokument>" >> $XML_META_FILENAME
        echo "          <typ>${DOCUMENT_FILE_TYPE}</typ>" >> $XML_META_FILENAME
        echo "          <nazev>${DOCUMENT_NAME}</nazev>" >> $XML_META_FILENAME
        echo "          <url_dokumentu>${DOCUMENT_URL}</url_dokumentu>" >> $XML_META_FILENAME
        echo "          <text>${DOCUMENT_TEXT_XML}</text>" >> $XML_META_FILENAME
        echo "          <md5>${DOCUMENT_MD5}</md5>" >> $XML_META_FILENAME
        echo "      </dokument>" >> $XML_META_FILENAME

        # JSON

        if $FIRST_DOCUMENT ; then
            FIRST_DOCUMENT=false
        else
            echo -n "," >> $JSON_FILENAME
        fi

        DOCUMENT_NAME_JSON=$(kcnd_json_escape "${DOCUMENT_NAME}")
        DOCUMENT_TEXT_JSON=$(kcnd_json_escape "${DOCUMENT_RAW_TEXT}")
        DOCUMENT_FILE_TYPE_JSON=$(kcnd_json_escape "${DOCUMENT_FILE_TYPE}")

        echo -n "{" >> $JSON_FILENAME
        echo -n "\"typ\":\"${DOCUMENT_FILE_TYPE_JSON}\"," >> $JSON_FILENAME
        echo -n "\"nazev\":\"${DOCUMENT_NAME_JSON}\"," >> $JSON_FILENAME
        echo -n "\"url_dokumentu\":\"${DOCUMENT_URL}\"," >> $JSON_FILENAME
        echo -n "\"text\":\"${DOCUMENT_TEXT_JSON}\"," >> $JSON_FILENAME
        echo -n "\"md5\":\"${DOCUMENT_MD5}\"" >> $JSON_FILENAME
        echo -n "}" >> $JSON_FILENAME
	done < /tmp/contract_parts

    # XML
    echo '  </dokumenty>' >> $XML_META_FILENAME
    echo '</smlouva>' >> $XML_META_FILENAME

    # JSON
    echo -n "]" >> $JSON_FILENAME
    echo -n "}" >> $JSON_FILENAME

    echo "Posílám na elasticsearch smlouvu s id $CURR_CONTRACT_ID"

    # Odeslání JSONu na elasticsearch
    RESPONSE=$(curl --silent -XPOST "http://localhost:9200/smlouvy/mfcr/" --data-binary "@${JSON_FILENAME}")
            
    if [[ $RESPONSE == *"\"error\""* ]]; then
        echo "$CURR_CONTRACT_ID // $RESPONSE" >> ../../$FAILED_TO_INDEX_FILENAME
        echo "Chyba, elasticsearch smlouvu $CURR_CONTRACT_ID nepřijal, záznam je v $FAILED_TO_INDEX_FILENAME"
    else
        echo "OK, smlouva $CURR_CONTRACT_ID zaindexována"
    fi

    cd ../../contracts_sources

done

cd ..

# Zabití Tika serveru
kill $TIKA_PID
