# Picture Sort Script

Dieses Bash-Skript sortiert Fotos anhand der EXIF-Daten des Kameramodells und des Aufnahmezeitpunkts.

## Voraussetzungen

- Linux oder eine kompatible Bash-Umgebung
- Bash
- `exiftool`
- Standardprogramme: `find`, `stat`, `sed`, `tr`, `mkdir`, `mv`

`exiftool` muss im `PATH` verfügbar sein.

## Verwendung

```bash
bash sort_new.sh /absoluter/pfad/zum/input-ordner /absoluter/pfad/zum/output-ordner
```

Beispiel:

```bash
bash sort_new.sh /mnt/fotos/import /mnt/fotos/sortiert
```

Beide Pfade müssen absolut sein. Vor dem Sortieren wartet das Skript auf eine Bestätigung per Enter.

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
6. Passende RAW-Dateien werden über denselben Basisnamen gesucht. Wenn mehrere Kandidaten gefunden werden, wird der zeitlich nächste Änderungszeitpunkt zum JPG verwendet.
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
- Der Ausgabeordner sollte nicht innerhalb des Eingabeverzeichnisses liegen, damit bereits sortierte Dateien nicht erneut berücksichtigt werden.
- Die Ordner `VIDEO` werden angelegt, aber in der aktuellen Skriptversion werden keine Videodateien verarbeitet.
- Die Dateiendungen der verschobenen Dateien bleiben erhalten.
- Das Skript ist aktuell nicht ausführbar markiert. Deshalb wird es mit `bash sort_new.sh ...` gestartet.

## Bekannte Überspringgründe

Das Skript überspringt ein JPG, wenn:

- kein Kameramodell ausgelesen werden kann oder
- kein `SubSecDateTimeOriginal` beziehungsweise `DateTimeOriginal` vorhanden ist.

Wenn keine passende RAW-Datei gefunden wird, wird das JPG trotzdem verschoben und eine Warnung ausgegeben.
