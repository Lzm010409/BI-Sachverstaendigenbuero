#!/usr/bin/env python3
"""LF6 Durchlaufzeiten: neues Dashboard + 2 Inline-Cards (lesen core.fact_ausbuchung,
laufen also schon vor dem sql/039-Deploy). Die 'wo klemmt es'-Stage-Card (v_stage_offen)
kommt nach dem Deploy."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=90)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:300]}
def q(s): return {"database":DB,"type":"native","native":{"query":s}}
def card(name,display,sql,viz,desc):
    r=api("POST","/api/card",{"name":name,"display":display,"dataset_query":q(sql),
          "visualization_settings":viz,"collection_id":COLL,"description":desc})
    print("card",r.get("id"),name[:50]); return r["id"]

# --- Card 1: Kennzahlen-Zusammenfassung (Median/Ø/P90) ---
c1_sql="""
WITH d AS (
  SELECT round(EXTRACT(EPOCH FROM (won_time - add_time))/86400.0,1) AS tage
  FROM core.fact_ausbuchung
  WHERE won_time IS NOT NULL AND add_time >= DATE '2024-11-01'
)
SELECT count(*) AS "Fälle (won)",
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY tage)::numeric,1) AS "Median Tage",
       round(avg(tage),1) AS "Ø Tage",
       round(percentile_cont(0.9) WITHIN GROUP (ORDER BY tage)::numeric,1) AS "P90 Tage"
FROM d WHERE tage IS NOT NULL"""
c1=card("Durchlaufzeit Intake→Bezahlt — Kennzahlen","table",c1_sql,{},
    "LF6 — Gesamt-Durchlaufzeit vom Anlegen des Falls (add_time) bis zur Bezahlung "
    "(won_time), nur bezahlte Fälle ab 2024-11 (vor Go-Live-Import verzerrt). "
    "Median statt Ø, weil einzelne Langläufer (Klage) den Schnitt hochziehen.")

# --- Card 2: Trend je Monat (Median-Linie + Volumen-Balken) ---
c2_sql="""
SELECT date_trunc('month', won_time)::date AS "Monat",
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY
         round(EXTRACT(EPOCH FROM (won_time-add_time))/86400.0,1))::numeric,1) AS "Median Tage",
       count(*) AS "Fälle (won)"
FROM core.fact_ausbuchung
WHERE won_time IS NOT NULL AND add_time >= DATE '2024-11-01'
GROUP BY 1 ORDER BY 1"""
c2_viz={"graph.dimensions":["Monat"],"graph.metrics":["Median Tage","Fälle (won)"],
        "graph.x_axis.title_text":"Monat (bezahlt)","graph.y_axis.title_text":"Tage / Fälle",
        "series_settings":{"Median Tage":{"display":"line","line.interpolate":"linear"},
                           "Fälle (won)":{"display":"bar"}}}
c2=card("Durchlaufzeit-Trend je Monat (Median)","combo",c2_sql,c2_viz,
    "LF6 — Median-Durchlaufzeit je Bezahlmonat (Linie) gegen Fallvolumen (Balken). "
    "Steigt die Linie bei hohem Volumen, ist es ein Kapazitätsengpass.")

# --- neues Dashboard anlegen ---
d=api("POST","/api/dashboard",{"name":"7 · Durchlaufzeiten & Engpässe (LF6)",
      "collection_id":COLL,
      "description":"Wie lange dauert ein Fall vom Eingang bis zur Bezahlung, und wo "
                    "stapeln sich offene Fälle? (LF6)"})
dash_id=d["id"]; print("dashboard",dash_id,d.get("name"))

dcs=[
 {"id":-1,"card_id":c1,"col":0,"row":0,"size_x":24,"size_y":4,"parameter_mappings":[],"visualization_settings":{}},
 {"id":-2,"card_id":c2,"col":0,"row":4,"size_x":24,"size_y":9,"parameter_mappings":[],"visualization_settings":{}},
]
api("PUT","/api/dashboard/%d"%dash_id,{"dashcards":dcs})
print("dashboard",dash_id,"-> 2 cards")
print("DASH_ID=%d C1=%d C2=%d"%(dash_id,c1,c2))
