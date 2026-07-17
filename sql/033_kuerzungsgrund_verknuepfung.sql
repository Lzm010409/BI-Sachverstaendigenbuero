-- 033_kuerzungsgrund_verknuepfung.sql — Kürzungsgrund aus dem Brief an die Zahlung
--
-- Arbeitsteilung (Inhaber): der zahlungsbasierte Weg (sql/032) liefert BETRAG +
-- Durchsetzungsquote zuverlässig; das Kürzungsschreiben liefert den GRUND (seine
-- Stärke). Verknüpfung über das Aktenzeichen. Der grobe Grund steht ohnehin schon im
-- Pipedrive-Ausbuchungsgrund (v_durchsetzung_zahlung.kuerzungsgrund); der Brief
-- ergänzt den detaillierten Grund (`kuerzungsgrund_brief`), sobald die OCR ihn liefert.
--
-- fact_kuerzungsereignis um kuerzungsgrund erweitert (aus dem LLM-Extrakt; die OCR
-- muss das Feld künftig setzen — Prompt-Erweiterung im Live-WF 4JgVp4tCzNHkPCpg).
-- Bis dahin bleibt die Spalte null (kein Bruch, kein Fehlwert).

CREATE OR REPLACE VIEW core.fact_kuerzungsereignis AS
SELECT
  aktenzeichen,
  letter_key,
  (payload->>'kuerzungsbetrag')::numeric(12,2)          AS kuerzungsbetrag,
  payload->>'versicherer'                                AS versicherer,
  payload->>'schadennummer'                             AS schadennummer,
  (NULLIF(payload->>'datum',''))::date                  AS datum,
  (payload->>'sachverstaendigenkosten')::numeric(12,2)  AS sv_kosten_gezahlt,
  (payload->>'zahlungsbetrag')::numeric(12,2)           AS zahlungsbetrag,
  quelle,
  extracted_at,
  -- NEU: Kürzungsgrund (kurze Kategorie aus dem Schreiben; null bis OCR ihn liefert).
  NULLIF(trim(payload->>'kuerzungsgrund'), '')          AS kuerzungsgrund
FROM raw.kuerzungsschreiben
WHERE aktenzeichen IS NOT NULL;

-- --- Zahlungsbasierte Durchsetzung + Brief-Grund (Betrag/Quote aus Zahlung, ------
--     detaillierter Grund aus dem Schreiben; grober Grund bleibt aus Pipedrive) ---
CREATE OR REPLACE VIEW marts.v_durchsetzung_zahlung_grund AS
WITH brief_grund AS (
  SELECT aktenzeichen, max(kuerzungsgrund) AS kuerzungsgrund_brief
  FROM core.fact_kuerzungsereignis
  WHERE kuerzungsgrund IS NOT NULL
  GROUP BY aktenzeichen
)
SELECT
  dz.*,
  bg.kuerzungsgrund_brief
FROM marts.v_durchsetzung_zahlung dz
LEFT JOIN brief_grund bg ON bg.aktenzeichen = dz.aktenzeichen;
