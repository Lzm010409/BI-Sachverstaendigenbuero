-- 047_gutachten_feed_recleanup.sql — Feed-Zeilen erneut zurücksetzen nach Parser-Fix
--
-- Der 2. Feed-Lauf füllte beurteilung + Nutzungsausfall korrekt, ließ aber WBW/
-- Reparaturkosten/Schadenhöhe/Dauer NULL (Parser war auf die Zusammenfassungs-TABELLE
-- angesetzt, die pdf-parse umordnet). parse-fachwerte.ts ist jetzt auf die FLIESSTEXT-
-- Vorkommen umgestellt und an echtem Gutachtentext verifiziert (alle Werte korrekt).
--
-- Diese Migration löscht die vom Feed erzeugten (unvollständigen) Zeilen erneut und
-- leert das Versuchsprotokoll → der nächste Lauf zieht sie mit dem korrigierten Parser
-- vollständig neu. Backfill-Zeilen (Dateiname statt 'autoixpert:%') bleiben unberührt.
-- Kein Quelldatenverlust: die Werte stehen jederzeit im Gutachten-PDF.

DELETE FROM raw.gutachten_fachwerte WHERE quelle_datei LIKE 'autoixpert:%';
DELETE FROM raw.gutachten_fetch_log;
