# Picture Sort Script

Dieses Bash-Skript sortiert Fotos anhand der EXIF-Daten des Kameramodells und des Aufnahmezeitpunkts.

## Voraussetzungen

- Linux oder eine kompatible Bash-Umgebung
- Bash
- `exiftool`
- Standardprogramme: `find`, `realpath`, `tr`, `mkdir`, `mv`

`exiftool` muss im `PATH` verfügbar sein.

## Verwendung

```bash
bash sort_new_v3.sh /absoluter/pfad/zum/input-ordner /absoluter/pfad/zum/output-ordner
```

Für einen automatisierten Lauf ohne Rückfrage:

```bash
bash sort_new_v3.sh --yes /absoluter/pfad/zum/input-ordner /absoluter/pfad/zum/output-ordner
```

Beispiel:

```bash
bash sort_new_v3.sh /mnt/fotos/import /mnt/fotos/sortiert
```

Beide Pfade müssen absolut sein. Ohne `--yes` muss die Sicherheitsabfrage exakt mit `YES` bestätigt werden.

## Funktionsweise

1. Das Eingabeverzeichnis wird rekursiv nach `.jpg`- und `.jpeg`-Dateien durchsucht.
2. Für jedes Bild werden Kameramodell und `SubSecDateTimeOriginal` beziehungsweise `DateTimeOriginal` ausgelesen.
3. Bilder ohne Kameramodell oder Aufnahmezeitpunkt werden übersprungen.
4. Für jedes Kameramodell werden folgende Verzeichnisse im Ausgabeordner angelegt:

   ```text
   <Ausgabeordner>/
   └── <Kameramodell>/
       ├── JPG/
       ├── RAW/
       └── VIDEO/
   ```

5. Das JPG wird anhand des Aufnahmezeitpunkts umbenannt und in den jeweiligen `JPG`-Ordner verschoben.
6. Eine passende RAW-Datei wird nur im selben Quellordner, mit exakt gleichem Basisnamen und passendem Aufnahmezeitpunkt gesucht. Bei mehreren Kandidaten wird keine RAW-Datei automatisch verschoben.
7. Gefundene RAW-Dateien werden anhand ihrer EXIF-Zeit umbenannt und in den jeweiligen `RAW`-Ordner verschoben.
8. Bei Namenskonflikten wird automatisch `_1`, `_2` usw. angehängt.

Unterstützte RAW-Endungen:

- `.ARW`
- `.NEF`
- `.CR2`
- `.CR3`
- `.DNG`
- `.RAF`
- `.ORF`
- `.RW2`

Der Ordner `UNSORTED_RAW` innerhalb des Eingabeverzeichnisses wird bei der rekursiven Suche ausgeschlossen.

## Wichtige Hinweise

- Das Skript verschiebt Dateien mit `mv`; es erstellt keine Kopien und verfügt über keinen Dry-Run-Modus.
- Vor der ersten Verwendung sollte ein Backup der Eingabedateien vorhanden sein.
- Das Skript weist Ausgabeordner zurück, die identisch mit dem Eingabeverzeichnis sind oder darin liegen.
- Die Ordner `VIDEO` werden angelegt, aber in der aktuellen Skriptversion werden keine Videodateien verarbeitet.
- Die Dateiendungen der verschobenen Dateien bleiben erhalten.
- `sort_new_v3.sh` ist die robuste Version. Sie validiert Pfade und EXIF-Daten, verarbeitet Sonderzeichen in Dateinamen und rollt ein JPG zurück, wenn das zugehörige RAW nicht verschoben werden kann.

## Bekannte Überspringgründe

Das Skript überspringt ein JPG, wenn:

- kein Kameramodell ausgelesen werden kann oder
- kein `SubSecDateTimeOriginal` und kein `DateTimeOriginal` vorhanden ist oder das Datum ungültig ist.

Wenn keine passende RAW-Datei gefunden wird, wird das JPG trotzdem verschoben und eine Warnung ausgegeben.
