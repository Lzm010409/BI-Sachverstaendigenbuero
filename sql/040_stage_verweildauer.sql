-- 040_stage_verweildauer.sql — LF6 Stufe 2: exakte Verweildauer JE Stage
--
-- Stufe 1 (sql/039) hat nur die GESAMT-Durchlaufzeit (add_time→won_time) und das
-- Alter im AKTUELLEN Stage. Für „wie lange steckt ein Fall in JEDEM Stage" brauchen
-- wir die vollständige Stage-Historie. Pipedrive liefert die über
-- GET /v1/deals/{id}/changelog (Feld field_key='stage_id') — extrahiert vom
-- Flow-Extractor `etl/pipedrive/extract-deal-flow.ts` nach:
--
--   raw.pipedrive_deal_changelog  (eine Zeile je Deal, payload = komplettes
--                                  changelog-data[]-Array, UNVERÄNDERT/heilig)
--
-- HINWEIS FELDNAMEN: Der Timestamp je Changelog-Eintrag heißt lt. Doku `time`
-- (Format 'YYYY-MM-DD HH:MM:SS', UTC). Die View liest tolerant `time`ODER`log_time`,
-- damit sie nicht bricht, falls die API-Version das Feld anders benennt — nach dem
-- ersten echten Extrakt am Sample bestätigen (wie bei sevDesk) und ggf. via neuer
-- Migration verengen. old_value/new_value sind die Stage-IDs als Text.

CREATE TABLE IF NOT EXISTS raw.pipedrive_deal_changelog (
  deal_id          bigint       PRIMARY KEY,
  deal_update_time timestamptz,                 -- Wasserstand: payload.update_time des Deals
  entry_count      int          NOT NULL DEFAULT 0,
  payload          jsonb        NOT NULL,        -- komplettes changelog data[]-Array
  extracted_at     timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.pipedrive_deal_changelog IS
  'Roh: Pipedrive GET /v1/deals/{id}/changelog data[] je Deal, unverändert. Stage-Historie für LF6 Stufe 2.';

-- --- Stage-Wechsel entpackt (nur field_key='stage_id') -----------------------
CREATE OR REPLACE VIEW core.fact_stage_change AS
SELECT
  c.deal_id,
  COALESCE((e->>'time')::timestamptz, (e->>'log_time')::timestamptz) AS ts,
  NULLIF(e->>'old_value','')::int                                    AS von_stage,
  NULLIF(e->>'new_value','')::int                                    AS nach_stage
FROM raw.pipedrive_deal_changelog c,
     jsonb_array_elements(c.payload) AS e
WHERE e->>'field_key' = 'stage_id'
  AND COALESCE(e->>'time', e->>'log_time') IS NOT NULL;

-- --- Segmente: je Deal, wie lange in welchem Stage --------------------------
-- Jede Stage-Wechsel-Zeile ci beendet den Aufenthalt im von_stage. Der Start
-- dieses Aufenthalts ist der vorherige Wechsel (lag) bzw. add_time. Zusätzlich
-- ein terminales Segment: der letzte nach_stage bis won_time bzw. now().
CREATE OR REPLACE VIEW core.fact_stage_segment AS
WITH sc AS (
  SELECT sc.deal_id, sc.ts, sc.von_stage, sc.nach_stage,
         lag(sc.ts) OVER (PARTITION BY sc.deal_id ORDER BY sc.ts) AS prev_ts,
         row_number() OVER (PARTITION BY sc.deal_id ORDER BY sc.ts DESC) AS rn_desc
  FROM core.fact_stage_change sc
),
d AS (
  SELECT upper(regexp_replace(payload->>'title','\s','','g'))  AS aktenzeichen,
         id                                                     AS deal_id,
         (payload->>'add_time')::timestamptz                    AS add_time,
         (payload->>'won_time')::timestamptz                    AS won_time,
         payload->>'status'                                     AS status
  FROM raw.pipedrive_deals
  WHERE upper(regexp_replace(payload->>'title','\s','','g')) ~ '^\d{4}/\d+TG$'
)
-- geschlossene Segmente (Aufenthalt im von_stage, endet beim Wechsel)
SELECT d.aktenzeichen, d.deal_id, sc.von_stage AS stage_id,
       COALESCE(sc.prev_ts, d.add_time)                                        AS von_ts,
       sc.ts                                                                    AS bis_ts,
       round(EXTRACT(EPOCH FROM (sc.ts - COALESCE(sc.prev_ts, d.add_time)))/86400.0, 2) AS verweil_tage,
       false                                                                    AS ist_offen
FROM sc JOIN d USING (deal_id)
WHERE sc.von_stage IS NOT NULL
UNION ALL
-- terminales Segment (aktueller Stage bis won_time/now)
SELECT d.aktenzeichen, d.deal_id, sc.nach_stage AS stage_id,
       sc.ts                                                                    AS von_ts,
       COALESCE(d.won_time, now())                                              AS bis_ts,
       round(EXTRACT(EPOCH FROM (COALESCE(d.won_time, now()) - sc.ts))/86400.0, 2) AS verweil_tage,
       (d.won_time IS NULL)                                                     AS ist_offen
FROM sc JOIN d USING (deal_id)
WHERE sc.rn_desc = 1 AND sc.nach_stage IS NOT NULL;

-- --- LF6 Stufe 2: Ø/Median Verweildauer je Stage ----------------------------
CREATE OR REPLACE VIEW marts.v_stage_verweildauer AS
SELECT
  st.order_nr,
  st.stage,
  count(*)                                                                     AS anzahl_segmente,
  count(*) FILTER (WHERE seg.ist_offen)                                        AS davon_offen,
  round(avg(seg.verweil_tage), 1)                                             AS schnitt_tage,
  round(percentile_cont(0.5) WITHIN GROUP (ORDER BY seg.verweil_tage)::numeric, 1) AS median_tage,
  round(percentile_cont(0.9) WITHIN GROUP (ORDER BY seg.verweil_tage)::numeric, 1) AS p90_tage
FROM core.fact_stage_segment seg
JOIN core.dim_stage st USING (stage_id)
WHERE seg.verweil_tage >= 0
GROUP BY st.order_nr, st.stage;
