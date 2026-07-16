-- 013_core_forderungsverlust.sql — Phase 5: Ausbuchung aus den sevDesk-Belegen
--
-- Der Inhaber erstellt je Ausbuchung einen sevDesk-Beleg „Forderungsverlust
-- <Aktenzeichen>". Dessen Betrag ist die TATSÄCHLICHE Ausbuchung — eine eigene,
-- zuverlässige Quelle (vollständiger als die dünn befüllte Pipedrive-
-- `ausgebucht_betrag`). Damit wird die Durchsetzungsquote messbar:
--   Kürzung   = was der Versicherer einbehält (sevDesk-Rechnung, s. fact_kuerzung)
--   Ausbuchung= was am Ende abgeschrieben wird   (dieser Forderungsverlust-Beleg)
--   Durchsetzung = Kürzung − Ausbuchung; Quote = 1 − ΣAusbuchung/ΣKürzung.
--
-- Alle Beträge brutto (CLAUDE.md). Welches Betragsfeld der maßgebliche
-- Ausbuchungsbetrag ist (sumGross vs. sumNet), ist mit dem Inhaber final zu
-- bestätigen — Default brutto.

-- --- fact_forderungsverlust (Grain: ein Forderungsverlust-Beleg) --------------
CREATE OR REPLACE VIEW core.fact_forderungsverlust AS
SELECT
  aktenzeichen,
  id                                        AS voucher_id,
  payload->>'description'                    AS beleg_titel,
  (payload->>'voucherDate')::timestamptz     AS beleg_datum,
  payload->>'status'                         AS status,
  -- Ausbuchungsbetrag (brutto). Bad-Debt-Write-off: als Betrag positiv geführt.
  abs((payload->>'sumGross')::numeric(12,2)) AS forderungsverlust_brutto,
  abs((payload->>'sumNet')::numeric(12,2))   AS forderungsverlust_netto
FROM raw.sevdesk_vouchers;

-- --- marts ------------------------------------------------------------------

-- Durchsetzungsquote je Versicherer: Kürzung (sevDesk-Rechnungsdifferenz) vs.
-- Ausbuchung (Forderungsverlust-Beleg), aggregiert je Fall. Kein Forderungsverlust-
-- Beleg = nichts abgeschrieben = voll durchgesetzt (Ausbuchung 0).
-- Haftungsquote/USt-Einbehalt sind in fact_kuerzung bereits ausgeschlossen.
CREATE OR REPLACE VIEW marts.v_durchsetzung AS
WITH kuerzung AS (
  SELECT aktenzeichen,
         max(versicherer)         AS versicherer,   -- je Fall konstant
         sum(kuerzung_betrag)     AS kuerzung
  FROM core.fact_kuerzung
  WHERE kuerzung_betrag > 0
    AND NOT ist_haftungsquote
    AND NOT ist_mwst_einbehalt
  GROUP BY aktenzeichen
),
ausbuchung AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausbuchung
  FROM core.fact_forderungsverlust
  WHERE aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
)
SELECT
  COALESCE(k.versicherer, '(unbekannt)')                 AS versicherer,
  count(*)                                                AS anzahl_faelle,
  sum(k.kuerzung)                                         AS summe_kuerzung,
  sum(COALESCE(a.ausbuchung, 0))                          AS summe_ausbuchung,
  sum(k.kuerzung) - sum(COALESCE(a.ausbuchung, 0))        AS summe_durchgesetzt,
  1 - sum(COALESCE(a.ausbuchung, 0)) / NULLIF(sum(k.kuerzung), 0) AS durchsetzungsquote
FROM kuerzung k
LEFT JOIN ausbuchung a ON a.aktenzeichen = k.aktenzeichen
GROUP BY 1;

-- Diagnose je Fall: alle Größen nebeneinander — zum Verifizieren an Echtdaten
-- (Metabase). Zeigt insb., ob Rechnungsdifferenz (Kürzung), Pipedrive-Ausbuchung
-- und Beleg-Ausbuchung auseinanderlaufen (dann ist die Durchsetzung echt messbar)
-- oder deckungsgleich sind.
CREATE OR REPLACE VIEW marts.v_durchsetzung_diagnose AS
SELECT
  k.aktenzeichen,
  max(k.versicherer)                                     AS versicherer,
  sum(k.rechnung_brutto)                                 AS rechnung_brutto,
  sum(k.bezahlt)                                         AS bezahlt,
  sum(CASE WHEN k.kuerzung_betrag > 0 AND NOT k.ist_haftungsquote
                AND NOT k.ist_mwst_einbehalt
           THEN k.kuerzung_betrag ELSE 0 END)            AS kuerzung,
  max(k.ausgebucht_betrag)                               AS ausbuchung_pipedrive,
  COALESCE(fv.ausbuchung_beleg, 0)                       AS ausbuchung_beleg,
  bool_or(k.ist_haftungsquote)                           AS hat_haftungsquote
FROM core.fact_kuerzung k
LEFT JOIN (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausbuchung_beleg
  FROM core.fact_forderungsverlust GROUP BY aktenzeichen
) fv ON fv.aktenzeichen = k.aktenzeichen
GROUP BY k.aktenzeichen, fv.ausbuchung_beleg;
