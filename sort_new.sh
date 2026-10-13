#!/bin/bash

set -euo pipefail

echo -e "\u001B[34m This Script was made by Swaffeln and KortexGLXY. \u001B[0m"
echo -e "\u001B[34m EMAIL: swaffelnswaffeln@gmail.com \u001B[0m"

sleep 3

if [ $# -ne 2 ]; then
    echo "Usage: $0 /absoluter/pfad/zum/input/ordner /absoluter/pfad/zum/output/ordner"
    exit 1
fi

TARGET_DIR="$1"

if [[ "$TARGET_DIR" != /* ]]; then
    echo -e "\u001B[31mFehler: Bitte einen absoluten Pfad angeben.\u001B[0m"
    exit 1
fi

OUTPUT_DIR="$2"

if [[ "$OUTPUT_DIR" != /* ]]; then
    echo -e "\u001B[31mFehler: Bitte einen absoluten Pfad angeben.\u001B[0m"
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo -e "\u001B[31mFehler: Ordner existiert nicht: $TARGET_DIR\u001B[0m"
    exit 1
fi

read -p "Sicherheitscheck!!! Es wird rekursiv in '$TARGET_DIR' sortiert. Weiter? [Enter]"

UNSORTED_RAW_DIR="$TARGET_DIR/UNSORTED_RAW"

get_safe_model() {
    local file="$1"
    local model

    model=$(exiftool -api QuickTimeUTC=1 -s -s -s -Model "$file" 2>/dev/null || true)

    if [ -z "$model" ]; then
        return 1
    fi

    echo "$model" | tr '/:' '_'
}

get_exif_datetime() {
    local file="$1"
    exiftool -s -s -s -SubSecDateTimeOriginal "$file" 2>/dev/null || \
    exiftool -s -s -s -DateTimeOriginal "$file" 2>/dev/null || true
}

format_datetime_for_filename() {
    local dt="$1"
    dt="${dt%%+*}"
    echo "$dt" | sed 's/:/./; s/:/./; s/ /-/'
}

unique_target_path() {
    local dir="$1"
    local base="$2"
    local ext="$3"
    local candidate="$dir/${base}.${ext}"
    local counter=1

    while [ -e "$candidate" ]; do
        candidate="$dir/${base}_$counter.${ext}"
        counter=$((counter + 1))
    done

    echo "$candidate"
}

find_best_raw() {
    local jpg_path="$1"
    local jpg_base="$2"
    local jpg_mtime
    local best_raw=""
    local best_diff=""
    local candidate
    local candidate_mtime
    local diff

    jpg_mtime=$(stat -c %Y "$jpg_path")

    while IFS= read -r candidate; do
        [ "$candidate" = "$jpg_path" ] && continue

        candidate_mtime=$(stat -c %Y "$candidate")
        diff=$(( jpg_mtime - candidate_mtime ))
        if [ "$diff" -lt 0 ]; then
            diff=$(( -diff ))
        fi

        if [ -z "$best_diff" ] || [ "$diff" -lt "$best_diff" ]; then
            best_diff="$diff"
            best_raw="$candidate"
        fi
    done < <(
        find "$TARGET_DIR" \
            -path "$UNSORTED_RAW_DIR" -prune -o \
            -type f \( \
                -iname "${jpg_base}.ARW" -o -iname "${jpg_base}.NEF" -o \
                -iname "${jpg_base}.CR2" -o -iname "${jpg_base}.CR3" -o \
                -iname "${jpg_base}.DNG" -o -iname "${jpg_base}.RAF" -o \
                -iname "${jpg_base}.ORF" -o -iname "${jpg_base}.RW2" \
            \) -print
    )

    if [ -n "$best_raw" ]; then
        printf '%s
' "$best_raw"
    fi
}

# HAUPTSCRIPT

find "$TARGET_DIR" \
    -path "$UNSORTED_RAW_DIR" -prune -o \
    -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) -print | while IFS= read -r JPG; do

    MODEL="$(get_safe_model "$JPG" || true)"

    if [ -z "$MODEL" ]; then
        echo -e "\u001B[31mNo cam model for $JPG – skip...\u001B[0m"
        continue
    fi

    JPG_DATETIME="$(get_exif_datetime "$JPG")"
    if [ -z "$JPG_DATETIME" ]; then
        echo -e "\u001B[31mNo DateTimeOriginal for $JPG – skip...\u001B[0m"
        continue
    fi

    DEST_BASE="$OUTPUT_DIR/$MODEL"
    JPG_DIR="$DEST_BASE/JPG"
    RAW_DIR="$DEST_BASE/RAW"
    VIDEO_DIR="$DEST_BASE/VIDEO"

    mkdir -p "$JPG_DIR" "$RAW_DIR" "$VIDEO_DIR"

    BASENAME="$(basename "${JPG%.*}")"
    BEST_RAW="$(find_best_raw "$JPG" "$BASENAME")"

    JPG_EXT="${JPG##*.}"
    JPG_NEW_BASENAME="$(format_datetime_for_filename "$JPG_DATETIME")"
    JPG_TARGET="$(unique_target_path "$JPG_DIR" "$JPG_NEW_BASENAME" "$JPG_EXT")"

    mv "$JPG" "$JPG_TARGET"

    if [ -n "${BEST_RAW:-}" ] && [ -e "$BEST_RAW" ]; then
        RAW_EXT="${BEST_RAW##*.}"
        RAW_DATETIME="$(get_exif_datetime "$BEST_RAW")"

        if [ -n "$RAW_DATETIME" ]; then
            RAW_NEW_BASENAME="$(format_datetime_for_filename "$RAW_DATETIME")"
        else
            RAW_NEW_BASENAME="$JPG_NEW_BASENAME"
        fi

        RAW_TARGET="$(unique_target_path "$RAW_DIR" "$RAW_NEW_BASENAME" "$RAW_EXT")"
        mv "$BEST_RAW" "$RAW_TARGET"
        echo -e "\u001B[32mRAW matched: $BEST_RAW -> $RAW_TARGET\u001B[0m"
    else
        echo -e "\u001B[33mNo RAW found for $JPG\u001B[0m"
    fi

    echo -e "\u001B[32mDone with $(basename "$JPG") from cam model: $MODEL\u001B[0m"
done

echo -e "\u001B[32mFERTIG!!!\u001B[0m"
