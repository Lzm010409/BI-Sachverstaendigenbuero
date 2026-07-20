-- 045_gutachten_feed_cleanup.sql — vom Gutachten-Feed fehlerhaft erzeugte Zeilen bereinigen
--
-- Der erste Feed-Lauf (2026-07-20) hat mit einem Parser gearbeitet, dessen Regexes
-- das ECHTE autoiXpert-Zusammenfassungsformat nicht trafen (Format war „EUR <Betrag>",
-- real ist „<Betrag> €"; beurteilung fing das Fließtext-„der" aus „Bei der Beurteilung
-- der Reparaturdauer"). Ergebnis: 19 Zeilen mit beurteilung='der' + lauter NULLs.
--
-- parse-fachwerte.ts ist korrigiert (an echten PDFs verifiziert). Diese Migration löscht
-- die fehlerhaften Feed-Zeilen (NUR die vom Feed erzeugten, quelle_datei 'autoixpert:%';
-- die Backfill-Zeilen mit Dateinamen bleiben unberührt) und leert das Versuchsprotokoll,
-- damit der nächste Feed-Lauf sie mit dem korrigierten Parser neu zieht.
-- Kein Verlust an Quelldaten: die Werte stehen jederzeit wieder im Gutachten-PDF.

DELETE FROM raw.gutachten_fachwerte WHERE quelle_datei LIKE 'autoixpert:%';
DELETE FROM raw.gutachten_fetch_log;
