-- 004_marts.sql — Metabase-Views (Phase 2)
--
-- v_ausbuchung_monat: Ausbuchungssumme und -quote je Monat und Organisation,
-- ausschließlich über erfasste Deals (ausgebucht_betrag IS NOT NULL).
--
--   Ausbuchungsquote = Σ ausgebucht_betrag / Σ deal_value_brutto
--                      WHERE ausgebucht_betrag IS NOT NULL
--
-- 0 zählt mit (= geprüft, voll bezahlt); NULL wird durch ist_erfasst gefiltert.

CREATE OR REPLACE VIEW marts.v_ausbuchung_monat AS
SELECT
  date_trunc('month', f.won_time)::date        AS monat,
  f.org_id,
  o.name                                       AS organisation,
  o.typ                                        AS organisation_typ,
  count(*)                                     AS anzahl_deals,
  sum(f.ausgebucht_betrag)                     AS ausgebucht_summe,
  sum(f.deal_value_brutto)                     AS basis_summe,
  sum(f.ausgebucht_betrag)
    / NULLIF(sum(f.deal_value_brutto), 0)      AS ausbuchungsquote
FROM core.fact_ausbuchung f
LEFT JOIN core.dim_organisation o ON o.org_id = f.org_id
WHERE f.ist_erfasst = true
  AND f.won_time IS NOT NULL
GROUP BY 1, 2, 3, 4;
