#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="$(basename -- "$0")"
PROCESSED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

print_error() {
    printf '\033[31mFehler: %s\033[0m\n' "$*" >&2
}

print_warning() {
    printf '\033[33mWarnung: %s\033[0m\n' "$*" >&2
}

print_success() {
    printf '\033[32m%s\033[0m\n' "$*"
}

usage() {
    cat <<EOF
Verwendung:
  $SCRIPT_NAME [--yes] /absoluter/pfad/zum/input-ordner /absoluter/pfad/zum/output-ordner

Ohne --yes verlangt das Skript eine ausdrückliche Bestätigung mit YES.
EOF
}

fail() {
    print_error "$*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Benötigtes Programm fehlt: $1"
}

if [[ "$#" -eq 2 ]]; then
    AUTO_CONFIRM=false
    TARGET_DIR="$1"
    OUTPUT_DIR="$2"
elif [[ "$#" -eq 3 && "$1" == "--yes" ]]; then
    AUTO_CONFIRM=true
    TARGET_DIR="$2"
    OUTPUT_DIR="$3"
else
    usage >&2
    exit 1
fi

if [[ "$TARGET_DIR" != /* || "$OUTPUT_DIR" != /* ]]; then
    fail "Input- und Output-Pfad müssen absolut sein."
fi

require_command exiftool
require_command find
require_command realpath
require_command mv
require_command mkdir
require_command tr

[[ -d "$TARGET_DIR" ]] || fail "Input-Ordner existiert nicht: $TARGET_DIR"

TARGET_CANONICAL="$(realpath -e -- "$TARGET_DIR")"
OUTPUT_CANONICAL="$(realpath -m -- "$OUTPUT_DIR")"

[[ "$TARGET_CANONICAL" != "/" ]] || fail "Das Root-Verzeichnis darf nicht als Input verwendet werden."
[[ "$TARGET_CANONICAL" != "$OUTPUT_CANONICAL" ]] || fail "Input- und Output-Ordner dürfen nicht identisch sein."

case "$OUTPUT_CANONICAL/" in
    "$TARGET_CANONICAL/"*)
        fail "Der Output-Ordner darf nicht innerhalb des Input-Ordners liegen."
        ;;
esac

if [[ "$AUTO_CONFIRM" == false ]]; then
    printf 'Sicherheitscheck: Rekursiv in "%s" sortieren. Zum Fortfahren YES eingeben: ' "$TARGET_CANONICAL"
    if ! read -r CONFIRMATION; then
        fail "Keine Bestätigung erhalten."
    fi
    [[ "$CONFIRMATION" == "YES" ]] || fail "Vorgang abgebrochen."
fi

mkdir -p -- "$OUTPUT_CANONICAL"
[[ -d "$OUTPUT_CANONICAL" && -w "$OUTPUT_CANONICAL" ]] || fail "Output-Ordner ist nicht beschreibbar: $OUTPUT_CANONICAL"

UNSORTED_RAW_DIR="$TARGET_CANONICAL/UNSORTED_RAW"

get_safe_model() {
    local file="$1"
    local model
    local safe_model

    model="$(exiftool -api QuickTimeUTC=1 -s -s -s -Model "$file" 2>/dev/null || true)"
    [[ -n "$model" ]] || return 1

    # Nur sichere Dateinamenzeichen erlauben; auch Newlines und Steuerzeichen werden ersetzt.
    safe_model="$(printf '%s' "$model" | LC_ALL=C tr -c 'A-Za-z0-9._ -' '_')"
    case "$safe_model" in
        ""|"."|"..") safe_model="UnknownModel" ;;
    esac

    printf '%s\n' "$safe_model"
}

get_exif_datetime() {
    local file="$1"
    local datetime

    datetime="$(exiftool -s -s -s -SubSecDateTimeOriginal "$file" 2>/dev/null || true)"

    # Nicht den Exitcode, sondern die tatsächlich gelieferte Ausgabe prüfen.
    if [[ -z "$datetime" ]]; then
        datetime="$(exiftool -s -s -s -DateTimeOriginal "$file" 2>/dev/null || true)"
    fi

    datetime="${datetime//$'\r'/}"
    printf '%s\n' "$datetime"
}

format_datetime_for_filename() {
    local datetime="$1"
    local year month day hour minute second

    if [[ "$datetime" =~ ^([0-9]{4}):([0-9]{2}):([0-9]{2})[[:space:]]+([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]+)?([+-][0-9]{2}:[0-9]{2})?$ ]]; then
        year="${BASH_REMATCH[1]}"
        month="${BASH_REMATCH[2]}"
        day="${BASH_REMATCH[3]}"
        hour="${BASH_REMATCH[4]}"
        minute="${BASH_REMATCH[5]}"
        second="${BASH_REMATCH[6]}"
        printf '%s.%s.%s-%s.%s.%s\n' "$year" "$month" "$day" "$hour" "$minute" "$second"
        return 0
    fi

    return 1
}

datetime_key() {
    local datetime="$1"

    if [[ "$datetime" =~ ^([0-9]{4}):([0-9]{2}):([0-9]{2})[[:space:]]+([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
        printf '%s%s%s%s%s%s\n' \
            "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
            "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}"
        return 0
    fi

    return 1
}

unique_target_path() {
    local directory="$1"
    local base="$2"
    local extension="$3"
    local candidate="$directory/${base}.${extension}"
    local counter=1

    while [[ -e "$candidate" || -L "$candidate" ]]; do
        candidate="$directory/${base}_${counter}.${extension}"
        counter=$((counter + 1))
    done

    printf '%s\n' "$candidate"
}

is_supported_raw_extension() {
    case "${1,,}" in
        arw|nef|cr2|cr3|dng|raf|orf|rw2) return 0 ;;
        *) return 1 ;;
    esac
}

find_matching_raw() {
    local jpg_path="$1"
    local jpg_base="$2"
    local jpg_datetime_key="$3"
    local jpg_directory
    local candidate
    local candidate_filename
    local candidate_base
    local candidate_extension
    local candidate_datetime
    local candidate_datetime_key
    local -a matches=()

    jpg_directory="$(dirname -- "$jpg_path")"

    # Nur im selben Quellordner und nur mit exakt gleichem Basisnamen suchen.
    while IFS= read -r -d '' candidate; do
        candidate_filename="$(basename -- "$candidate")"
        candidate_base="${candidate_filename%.*}"
        candidate_extension="${candidate_filename##*.}"

        [[ "${candidate_base,,}" == "${jpg_base,,}" ]] || continue
        is_supported_raw_extension "$candidate_extension" || continue

        candidate_datetime="$(get_exif_datetime "$candidate")"
        if [[ -n "$candidate_datetime" ]]; then
            candidate_datetime_key="$(datetime_key "$candidate_datetime" || true)"
            if [[ -n "$candidate_datetime_key" && "$candidate_datetime_key" != "$jpg_datetime_key" ]]; then
                continue
            fi
        fi

        matches+=("$candidate")
    done < <(find "$jpg_directory" -maxdepth 1 -type f -print0)

    if [[ "${#matches[@]}" -eq 1 ]]; then
        printf '%s\n' "${matches[0]}"
    elif [[ "${#matches[@]}" -gt 1 ]]; then
        print_warning "Mehrere passende RAW-Dateien für $jpg_path gefunden; RAW wird nicht automatisch verschoben."
    fi
}

process_jpg() {
    local jpg="$1"
    local jpg_filename
    local jpg_base
    local model
    local jpg_datetime
    local jpg_datetime_key
    local jpg_new_basename
    local destination_base
    local jpg_directory
    local raw_directory
    local video_directory
    local best_raw
    local jpg_extension
    local raw_extension
    local raw_datetime
    local raw_new_basename
    local jpg_target
    local raw_target

    jpg_filename="$(basename -- "$jpg")"
    jpg_base="${jpg_filename%.*}"

    if [[ -z "$jpg_base" || "$jpg_base" == "$jpg_filename" ]]; then
        print_warning "Ungültiger JPG-Dateiname, übersprungen: $jpg"
        ((SKIPPED_COUNT += 1))
        return 0
    fi

    model="$(get_safe_model "$jpg" || true)"
    if [[ -z "$model" ]]; then
        print_warning "Kein Kameramodell für $jpg; übersprungen."
        ((SKIPPED_COUNT += 1))
        return 0
    fi

    jpg_datetime="$(get_exif_datetime "$jpg")"
    if [[ -z "$jpg_datetime" ]]; then
        print_warning "Kein DateTimeOriginal für $jpg; übersprungen."
        ((SKIPPED_COUNT += 1))
        return 0
    fi

    jpg_new_basename="$(format_datetime_for_filename "$jpg_datetime" || true)"
    jpg_datetime_key="$(datetime_key "$jpg_datetime" || true)"
    if [[ -z "$jpg_new_basename" || -z "$jpg_datetime_key" ]]; then
        print_warning "Ungültiges EXIF-Datum für $jpg; übersprungen."
        ((SKIPPED_COUNT += 1))
        return 0
    fi

    destination_base="$OUTPUT_CANONICAL/$model"
    jpg_directory="$destination_base/JPG"
    raw_directory="$destination_base/RAW"
    video_directory="$destination_base/VIDEO"
    mkdir -p -- "$jpg_directory" "$raw_directory" "$video_directory"

    best_raw="$(find_matching_raw "$jpg" "$jpg_base" "$jpg_datetime_key")"
    jpg_extension="${jpg_filename##*.}"
    jpg_target="$(unique_target_path "$jpg_directory" "$jpg_new_basename" "$jpg_extension")"

    if ! mv -- "$jpg" "$jpg_target"; then
        print_error "JPG konnte nicht verschoben werden: $jpg"
        ((FAILED_COUNT += 1))
        return 0
    fi

    if [[ -n "$best_raw" && -e "$best_raw" ]]; then
        raw_extension="${best_raw##*.}"
        raw_datetime="$(get_exif_datetime "$best_raw")"
        raw_new_basename="$jpg_new_basename"
        if [[ -n "$raw_datetime" ]]; then
            raw_new_basename="$(format_datetime_for_filename "$raw_datetime" || true)"
            [[ -n "$raw_new_basename" ]] || raw_new_basename="$jpg_new_basename"
        fi
        raw_target="$(unique_target_path "$raw_directory" "$raw_new_basename" "$raw_extension")"

        if ! mv -- "$best_raw" "$raw_target"; then
            print_error "RAW konnte nicht verschoben werden; JPG wird zurückgerollt: $best_raw"
            if ! mv -- "$jpg_target" "$jpg"; then
                print_error "Rollback fehlgeschlagen. JPG liegt weiterhin hier: $jpg_target"
            fi
            ((FAILED_COUNT += 1))
            return 0
        fi

        print_success "RAW verschoben: $best_raw -> $raw_target"
    else
        print_warning "Keine eindeutige passende RAW-Datei für $jpg gefunden."
    fi

    ((PROCESSED_COUNT += 1))
    print_success "JPG verschoben: $jpg -> $jpg_target"
}

printf '\033[34mPicture Sort Script v3\033[0m\n'
printf 'Input:  %s\nOutput: %s\n' "$TARGET_CANONICAL" "$OUTPUT_CANONICAL"

while IFS= read -r -d '' jpg_file; do
    process_jpg "$jpg_file"
done < <(
    find "$TARGET_CANONICAL" \
        -path "$UNSORTED_RAW_DIR" -prune -o \
        -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0
)

printf '\nZusammenfassung: %d verarbeitet, %d übersprungen, %d fehlgeschlagen.\n' \
    "$PROCESSED_COUNT" "$SKIPPED_COUNT" "$FAILED_COUNT"

if (( FAILED_COUNT > 0 )); then
    exit 1
fi

print_success "Fertig."
