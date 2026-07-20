-- 054_beauftragungsherkunft.sql — LF4: Auftragsherkunft-Kategorie je Fall
--
-- Der Inhaber kategorisiert die Beauftragungsherkunft je Geschädigtem in vier
-- Kanäle: WERKSTATT, INTERNET, DRITTE, RECHTSANWALT. Diese Angabe ist KEIN über
-- die Pipedrive-API abrufbares Feld (getPerson liefert dort null) — sie stammt aus
-- der Inhaber-Liste und wurde per NAMENSABGLEICH gegen die Pipedrive-Personen auf
-- die pseudonyme person_id aufgelöst (fixtures/beauftragungsherkunft.csv).
--
-- DSGVO: gespeichert werden nur person_id (Pseudonym) + Kategorie, keine Klarnamen.
-- Der Fallbezug läuft über deal.person_id (analog core.dim_fall_geo, sql/027).
--
-- Verhältnis zu v_auftragsquelle (sql/053): Dort ist die Quelle der KONKRETE
-- Vermittler (autoiXpert-intermediary, ab 2026) bzw. der historische Klartext.
-- HIER ist es der grobe KANAL. Beide Sichten ergänzen sich; diese beantwortet
-- LF4 auf Kanal-Ebene und deckt auch Altfälle vor 2026 ab.

-- --- Dimension: person_id -> Kanal (Fixture-geladen) ------------------------
CREATE TABLE IF NOT EXISTS core.dim_beauftragungsherkunft (
  person_id bigint PRIMARY KEY,
  kategorie text NOT NULL
    CHECK (kategorie IN ('WERKSTATT', 'INTERNET', 'DRITTE', 'RECHTSANWALT'))
);
COMMENT ON TABLE core.dim_beauftragungsherkunft IS
  'Beauftragungsherkunft-Kanal je pseudonymer person_id (Inhaber-Liste, per Namensabgleich aufgelöst). Quelle: fixtures/beauftragungsherkunft.csv. Keine Klarnamen.';

-- --- Fall -> Kanal (Grain: ein Aktenzeichen) --------------------------------
CREATE OR REPLACE VIEW core.dim_fall_beauftragungsherkunft AS
SELECT DISTINCT
  upper(regexp_replace(d.payload->>'title', '\s', '', 'g')) AS aktenzeichen,
  b.kategorie
FROM raw.pipedrive_deals d
JOIN core.dim_beauftragungsherkunft b
  ON b.person_id = NULLIF(d.payload->>'person_id', '')::bigint
WHERE upper(regexp_replace(d.payload->>'title', '\s', '', 'g')) ~ '^\d{4}/\d+TG$';

-- --- LF4: Kennzahlen je Kanal (won-Fälle) -----------------------------------
CREATE OR REPLACE VIEW marts.v_beauftragungsherkunft AS
SELECT
  COALESCE(h.kategorie, '(unbekannt)')                                        AS kategorie,
  count(*)                                                                    AS anzahl_faelle,
  round(sum(fa.deal_value_brutto))                                            AS summe_umsatz_brutto,
  round(avg(fa.deal_value_brutto))                                            AS schnitt_umsatz_brutto,
  -- Zahlungsausfall (Forderungsverlust): nur erfasste Ausbuchungen > 0 (null ≠ 0).
  round(sum(fa.ausgebucht_betrag) FILTER (WHERE fa.ausgebucht_betrag > 0))     AS summe_forderungsverlust,
  count(*) FILTER (WHERE fa.ausgebucht_betrag > 0)                            AS anzahl_mit_verlust,
  -- Ausfallquote = Forderungsverlust / Umsatz (nur zur groben Einordnung je Kanal).
  round(100.0 * COALESCE(sum(fa.ausgebucht_betrag) FILTER (WHERE fa.ausgebucht_betrag > 0), 0)
        / NULLIF(sum(fa.deal_value_brutto), 0), 1)                            AS ausfallquote_pct
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_fall_beauftragungsherkunft h USING (aktenzeichen)
WHERE fa.won_time IS NOT NULL
GROUP BY 1;

-- --- Abdeckung: wie viele won-Fälle haben einen Kanal? ----------------------
CREATE OR REPLACE VIEW marts.v_beauftragungsherkunft_abdeckung AS
SELECT
  count(*)                                                                    AS won_faelle,
  count(*) FILTER (WHERE h.kategorie IS NOT NULL)                             AS mit_kategorie,
  round(100.0 * count(*) FILTER (WHERE h.kategorie IS NOT NULL)
        / NULLIF(count(*), 0), 0)                                             AS abdeckung_pct
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_fall_beauftragungsherkunft h USING (aktenzeichen)
WHERE fa.won_time IS NOT NULL;
