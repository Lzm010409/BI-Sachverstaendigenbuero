-- 061_kpi_snapshot.sql — Kennzahlen-Verläufe: Snapshots der Headline-KPIs
--
-- Zweck: sichtbar machen, OB Änderungen wirken. Zwei Arten von Verlauf:
--   1. PERIODEN-Kennzahlen (Umsatz/Monat, Kürzung/Monat, Deckungsbeitrag/Monat,
--      Durchlaufzeit/Monat) sind aus datierten Quelldaten rekonstruierbar — dafür
--      existieren bereits v_*_monat-Views (volle Historie sofort, KEIN Snapshot nötig).
--   2. STICHTAGS-Kennzahlen (Durchsetzungsquote gesamt, Abdeckungsgrade, Datenqualität,
--      offene Fälle) lassen sich NICHT rückwirkend rekonstruieren: sie ändern sich mit
--      Backfill/Pflege und der aktuelle Stand überschreibt den alten. Genau die werden
--      hier periodisch weggeschrieben — nur so wird z. B. sichtbar, ob der
--      Kürzungsgrund-Backfill die Abdeckung Monat für Monat hebt.
--
-- Kadenz: monatlicher Bucket, idempotenter Upsert je nächtlichem ETL-Lauf. Innerhalb
-- des Monats aktualisiert sich die Zeile (letzter Stand), zum Monatswechsel entsteht die
-- nächste. Historie beginnt ab erstem Lauf (Stichtagswerte sind nicht rückholbar).

CREATE TABLE IF NOT EXISTS core.kpi_snapshot (
  snapshot_monat date        NOT NULL,   -- Monatserster (date_trunc('month', ...))
  kpi_key        text        NOT NULL,
  wert           numeric,
  erfasst_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (snapshot_monat, kpi_key)
);
COMMENT ON TABLE core.kpi_snapshot IS
  'Monatliche Snapshots der Stichtags-Headline-KPIs (Durchsetzung, Abdeckung, Qualität, Bestand). Gefüllt von etl/snapshot-kpis.ts aus marts.v_kpi_aktuell. Idempotenter Upsert je Monat.';

-- --- Aktueller Wert je Headline-KPI (Quelle des Snapshots) --------------------------
-- Eine Zeile je kpi_key mit dem AKTUELLEN Wert. Der Snapshot-Job schreibt genau das
-- monatlich weg. Neue KPI hier ergänzen -> wird ab nächstem Lauf mitgeschrieben.
CREATE OR REPLACE VIEW marts.v_kpi_aktuell AS
SELECT 'durchsetzung_pct'::text AS kpi_key,
       round(100.0*sum(summe_durchgesetzt)/NULLIF(sum(summe_kuerzung),0),1)::numeric AS wert
  FROM marts.v_durchsetzung_echt
UNION ALL SELECT 'versicherer_abdeckung_pct', pct_gesamt::numeric FROM marts.v_versicherer_abdeckung
UNION ALL SELECT 'herkunft_abdeckung_pct',    abdeckung_pct::numeric FROM marts.v_beauftragungsherkunft_abdeckung
UNION ALL SELECT 'gutachten_abdeckung_pct',   abdeckung_pct::numeric FROM marts.v_gutachten_abdeckung
UNION ALL SELECT 'honorar_konform_pct',
       round(100.0*count(*) FILTER (WHERE befund='konform')/NULLIF(count(*),0),1)::numeric
  FROM marts.v_honorar_konformitaet
UNION ALL SELECT 'kuerzungsgrund_abdeckung_pct',
       round(100.0*count(*) FILTER (WHERE kuerzungsgrund IS NOT NULL
              AND kuerzungsgrund NOT IN ('','(ohne Grund)'))/NULLIF(count(*),0),1)::numeric
  FROM core.fact_kuerzungsereignis
UNION ALL SELECT 'won_faelle_kum',
       count(*) FILTER (WHERE won_time IS NOT NULL)::numeric FROM core.fact_ausbuchung
UNION ALL SELECT 'umsatz_brutto_kum',
       round(sum(deal_value_brutto) FILTER (WHERE won_time IS NOT NULL))::numeric FROM core.fact_ausbuchung
UNION ALL SELECT 'forderungsverlust_kum',
       round(sum(ausgebucht_betrag) FILTER (WHERE ausgebucht_betrag>0))::numeric FROM core.fact_ausbuchung
UNION ALL SELECT 'offene_faelle',
       count(*) FILTER (WHERE status='open')::numeric FROM core.fact_ausbuchung;

-- --- Verlauf: Snapshots + Metadaten (Label/Einheit/Richtung) ------------------------
-- richtung: 'hoch' = höher ist besser, 'niedrig' = niedriger ist besser, 'neutral' = Volumen.
CREATE OR REPLACE VIEW marts.v_kpi_verlauf AS
SELECT
  s.snapshot_monat,
  s.kpi_key,
  meta.label,
  meta.einheit,
  meta.richtung,
  s.wert
FROM core.kpi_snapshot s
JOIN (VALUES
  ('durchsetzung_pct',             'Durchsetzungsquote (echt)',        '%',      'hoch'),
  ('versicherer_abdeckung_pct',    'Versicherer-Abdeckung',            '%',      'hoch'),
  ('herkunft_abdeckung_pct',       'Beauftragungsherkunft-Abdeckung',  '%',      'hoch'),
  ('gutachten_abdeckung_pct',      'Gutachten-Fachwerte-Abdeckung',    '%',      'hoch'),
  ('honorar_konform_pct',          'Honorar-Konformität (eig. Tab.)',  '%',      'hoch'),
  ('kuerzungsgrund_abdeckung_pct', 'Kürzungsgrund-Abdeckung',          '%',      'hoch'),
  ('won_faelle_kum',               'Won-Fälle (kumuliert)',            'Fälle',  'neutral'),
  ('umsatz_brutto_kum',            'Umsatz brutto (kumuliert)',        '€',      'hoch'),
  ('forderungsverlust_kum',        'Forderungsverlust (kumuliert)',    '€',      'niedrig'),
  ('offene_faelle',                'Offene Fälle (Bestand)',           'Fälle',  'neutral')
) AS meta(kpi_key, label, einheit, richtung) ON meta.kpi_key = s.kpi_key
ORDER BY s.kpi_key, s.snapshot_monat;
