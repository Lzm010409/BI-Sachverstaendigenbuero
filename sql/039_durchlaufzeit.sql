-- 039_durchlaufzeit.sql — Durchlaufzeiten (LF6), Stufe 1 aus vorhandenen Daten
--
-- Stufe 1 (diese Migration, ohne neue Extraktion): Gesamt-Durchlaufzeit
-- (add_time → won_time) je won-Fall + Alter offener Fälle im AKTUELLEN Stage
-- (now − stage_change_time) → zeigt „wo stapeln sich offene Fälle". Pipedrive liefert
-- nur den LETZTEN Stage-Wechsel, daher keine exakte Verweildauer je Stage — das ist
-- Stufe 2 (Flow-Extractor `extract-deal-flow`, separate Migration).
-- Go-Live-Import (2024-10) verzerrt add_time → in den Zeit-Views ab 2024-11 gefiltert.

CREATE OR REPLACE VIEW core.dim_stage AS
SELECT * FROM (VALUES
  (6,'Aufgenommen',1),(7,'In Bearbeitung',2),(8,'Versendet',3),
  (9,'Teilbezahlt',4),(10,'Bezahlt',5),(11,'Klage',6)
) AS s(stage_id, stage, order_nr);

CREATE OR REPLACE VIEW core.fact_durchlauf AS
SELECT
  upper(regexp_replace(payload->>'title','\s','','g'))       AS aktenzeichen,
  id                                                          AS deal_id,
  (payload->>'add_time')::timestamptz                         AS add_time,
  (payload->>'won_time')::timestamptz                         AS won_time,
  (payload->>'stage_change_time')::timestamptz                AS stage_change_time,
  (payload->>'stage_id')::int                                 AS stage_id,
  payload->>'status'                                          AS status,
  CASE WHEN payload->>'won_time' IS NOT NULL
       THEN round(EXTRACT(EPOCH FROM ((payload->>'won_time')::timestamptz - (payload->>'add_time')::timestamptz))/86400.0, 1)
  END                                                         AS durchlaufzeit_tage
FROM raw.pipedrive_deals
WHERE upper(regexp_replace(payload->>'title','\s','','g')) ~ '^\d{4}/\d+TG$';

-- --- LF6: Gesamt-Durchlaufzeit (won, Intake → Bezahlt) -----------------------
CREATE OR REPLACE VIEW marts.v_durchlaufzeit AS
SELECT
  count(*)                                                                  AS anzahl_won,
  round(avg(durchlaufzeit_tage), 1)                                        AS schnitt_tage,
  round(percentile_cont(0.5) WITHIN GROUP (ORDER BY durchlaufzeit_tage)::numeric, 1) AS median_tage,
  round(percentile_cont(0.9) WITHIN GROUP (ORDER BY durchlaufzeit_tage)::numeric, 1) AS p90_tage
FROM core.fact_durchlauf
WHERE durchlaufzeit_tage IS NOT NULL AND add_time >= DATE '2024-11-01';

-- --- LF6: Durchlaufzeit-Trend je won-Monat ----------------------------------
CREATE OR REPLACE VIEW marts.v_durchlaufzeit_monat AS
SELECT
  date_trunc('month', won_time)::date                                       AS monat,
  count(*)                                                                  AS anzahl_won,
  round(percentile_cont(0.5) WITHIN GROUP (ORDER BY durchlaufzeit_tage)::numeric, 1) AS median_tage
FROM core.fact_durchlauf
WHERE durchlaufzeit_tage IS NOT NULL AND add_time >= DATE '2024-11-01'
GROUP BY 1;

-- --- LF6: offene Fälle je Stage + Alterung (wo klemmt es) --------------------
CREATE OR REPLACE VIEW marts.v_stage_offen AS
SELECT
  s.order_nr,
  s.stage,
  count(*)                                                                  AS anzahl_offen,
  round(avg(EXTRACT(EPOCH FROM (now() - f.stage_change_time))/86400.0), 1)  AS schnitt_alter_tage,
  round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (now() - f.stage_change_time))/86400.0)::numeric, 1) AS median_alter_tage,
  count(*) FILTER (WHERE now() - f.stage_change_time > INTERVAL '30 days')  AS aelter_30_tage
FROM core.fact_durchlauf f
JOIN core.dim_stage s USING (stage_id)
WHERE f.status = 'open'
GROUP BY 1, 2;
