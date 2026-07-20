-- 048_gutachten_feed_final_reclean.sql — letzter Reset nach dem Spacing-Fix des Parsers
--
-- #DIAG-Kontrolle zeigte: pdf-parse hängt in der Zusammenfassung Label und Betrag OHNE
-- Leerzeichen aneinander („MwSt. (371,87 €)2.329,07 €"). Der Parser verlangte ein
-- Leerzeichen → Reparaturkosten/Schadenhöhe blieben NULL. Korrigiert (\s* statt \s+),
-- an echtem pdf-parse-Text verifiziert: ALLE Felder korrekt.
--
-- Setzt die vom Feed erzeugten (teil-)Zeilen ein letztes Mal zurück, damit der nächste
-- Lauf sie vollständig neu zieht. Backfill unberührt. Löscht auch die temporäre
-- '#DIAG'-Zeile mit.

DELETE FROM raw.gutachten_fachwerte WHERE quelle_datei LIKE 'autoixpert:%';
DELETE FROM raw.gutachten_fetch_log;
