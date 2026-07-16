-- 018_core_kuerzungsereignis.sql — Phase 5: echte Kürzung + Durchsetzungsquote
--
-- Aus den Kürzungsschreiben (raw.kuerzungsschreiben). Alle Beträge brutto.
-- Endlich die ECHTE Kürzung: Versicherer-Behauptung mit Betrag/Grund/Zeitpunkt.

-- --- fact_kuerzungsereignis (Grain: ein Kürzungsschreiben) -------------------
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
  extracted_at
FROM raw.kuerzungsschreiben
WHERE aktenzeichen IS NOT NULL;

-- --- marts ------------------------------------------------------------------

-- ECHTE Durchsetzungsquote: Kürzung (Schreiben) vs. Ausbuchung (Forderungsverlust-
-- Beleg). Kein Beleg = nichts abgeschrieben = voll durchgesetzt.
CREATE OR REPLACE VIEW marts.v_durchsetzung_echt AS
WITH kuerzung AS (
  SELECT aktenzeichen,
         max(versicherer)      AS versicherer,
         sum(kuerzungsbetrag)  AS kuerzung
  FROM core.fact_kuerzungsereignis
  WHERE kuerzungsbetrag > 0
  GROUP BY aktenzeichen
),
ausbuchung AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausbuchung
  FROM core.fact_forderungsverlust WHERE aktenzeichen IS NOT NULL GROUP BY aktenzeichen
)
SELECT
  COALESCE(NULLIF(trim(k.versicherer), ''), '(unbekannt)') AS versicherer,
  count(*)                                                 AS anzahl_faelle,
  sum(k.kuerzung)                                          AS summe_kuerzung,
  sum(COALESCE(a.ausbuchung, 0))                           AS summe_ausbuchung,
  sum(k.kuerzung) - sum(COALESCE(a.ausbuchung, 0))         AS summe_durchgesetzt,
  1 - sum(COALESCE(a.ausbuchung, 0)) / NULLIF(sum(k.kuerzung), 0) AS durchsetzungsquote
FROM kuerzung k
LEFT JOIN ausbuchung a ON a.aktenzeichen = k.aktenzeichen
GROUP BY 1;

-- Kürzung je Versicherer (LF2) — echte Kürzungsbeträge.
CREATE OR REPLACE VIEW marts.v_kuerzung_echt_je_versicherer AS
SELECT
  COALESCE(NULLIF(trim(versicherer), ''), '(unbekannt)') AS versicherer,
  count(*)                                                AS anzahl_schreiben,
  sum(kuerzungsbetrag)                                    AS summe_kuerzung,
  round(avg(kuerzungsbetrag), 2)                          AS schnitt_kuerzung
FROM core.fact_kuerzungsereignis
WHERE kuerzungsbetrag > 0
GROUP BY 1;
