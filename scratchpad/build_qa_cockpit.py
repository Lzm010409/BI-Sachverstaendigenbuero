#!/usr/bin/env python3
"""Stufe A3 — Datenqualitäts- & Betriebs-Cockpit (neues Dashboard). Zeigt Abdeckung
je Dimension, ETL-Laufstatus, Datenaktualität und Anomalien. Inline-SQL auf
bestehende core/marts-Views → sofort live."""
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
    print("card",r.get("id"),name[:45]); return r["id"]

# A: Abdeckung je Dimension (Balken %)
cA=card("Abdeckung je Dimension (% der won-Fälle)","bar","""
WITH w AS (SELECT * FROM core.fact_ausbuchung WHERE won_time IS NOT NULL)
SELECT 'Versicherer (LF2)' AS "Dimension", round(100.0*count(vk.versicherer)/count(*),0) AS "Abdeckung %"
  FROM w LEFT JOIN core.dim_versicherer_kanon vk ON vk.org_id=w.org_id
UNION ALL SELECT 'Anwalt (LF4)', round(100.0*count(anwalt_org_id)/count(*),0) FROM w
UNION ALL SELECT 'Gutachten-Fachwerte (LF8/10)',
  (SELECT round(100.0*count(g.aktenzeichen)/count(*),0) FROM core.fact_durchlauf fd LEFT JOIN core.fact_gutachten g USING(aktenzeichen) WHERE fd.won_time IS NOT NULL)
UNION ALL SELECT 'Geo/PLZ (LF7)',
  (SELECT round(100.0*count(dfg.plz_gebiet)/count(*),0) FROM core.fact_durchlauf fd LEFT JOIN core.dim_fall_geo dfg USING(aktenzeichen) WHERE fd.won_time IS NOT NULL)
ORDER BY 2 DESC""",
  {"graph.dimensions":["Dimension"],"graph.metrics":["Abdeckung %"],
   "graph.x_axis.title_text":"","graph.y_axis.title_text":"% der won-Fälle","graph.show_values":True},
  "Anteil der bezahlten Fälle, für die die jeweilige Dimension befüllt ist. Niedrige "
  "Abdeckung = Kennzahlen dieser Dimension nur eingeschränkt belastbar. Versicherer-"
  "Lücke wird über autoiXpert geschlossen (Stufe A1).")

# B: ETL-Laufstatus
cB=card("ETL-Laufstatus (letzte Läufe je Quelle)","table","""
SELECT source AS "Quelle", status AS "Status", rows AS "Zeilen",
       COALESCE(error,'') AS "Fehler", ran_at AS "Lauf"
FROM marts.v_etl_run ORDER BY ran_at DESC""",
  {"table.column_formatting":[{"columns":["Status"],"type":"single","operator":"!=",
     "value":"ok","color":"#ED6E6E","highlight_row":True}]},
  "Ergebnis der letzten ETL-Läufe je Quelle (aus dem Lauf-Protokoll). Rot = Fehler. "
  "Erste Anlaufstelle, wenn Zahlen nicht aktuell wirken.")

# C: Datenaktualität
cC=card("Datenaktualität je Quelle (Alter)","table","""
SELECT source AS "Quelle", last_run AS "Letzter Lauf",
       round(EXTRACT(EPOCH FROM (now()-last_run))/3600.0,1) AS "Alter (Std)"
FROM marts.v_etl_status ORDER BY last_run ASC""",
  {"table.column_formatting":[{"columns":["Alter (Std)"],"type":"single","operator":">",
     "value":48,"color":"#F9CF48","highlight_row":False}]},
  "Wie lange der letzte erfolgreiche Abzug je Quelle her ist. Gelb ab >48 Std → Quelle "
  "läuft evtl. nicht mehr durch (Deploy/Token prüfen).")

# D: Anomalien
cD=card("Datenqualitäts-Anomalien","table","""
SELECT 'Rechnungen: Summe ≠ Positionen' AS "Prüfung", count(*) AS "Treffer", 'sollte 0 sein' AS "Soll"
  FROM marts.v_rechnung_konsistenz WHERE differenz <> 0
UNION ALL SELECT 'Gutachten: netto×1,19 ≠ brutto', count(*), 'sollte 0 sein'
  FROM core.fact_gutachten WHERE reparaturkosten_netto>0 AND abs(reparaturkosten_netto*1.19-reparaturkosten_brutto)>1
UNION ALL SELECT 'Ausbuchung nie erfasst (null)', count(*), 'v.a. Altfälle, Info'
  FROM core.fact_ausbuchung WHERE ausgebucht_betrag IS NULL
UNION ALL SELECT 'Gutachten-Feed: Fehler/kein Report', count(*), 'sollte niedrig sein'
  FROM marts.v_gutachten_feed_log WHERE status IN ('fehler','kein_report')""",
  {"table.column_formatting":[{"columns":["Treffer"],"type":"single","operator":">",
     "value":0,"color":"#F9CF48","highlight_row":False}]},
  "Automatische Plausibilitätsprüfungen. netto×1,19≈brutto ist die Kern-Invariante der "
  "Beträge; Rechnungs-Summe muss den Positionen entsprechen. Treffer>0 = nachsehen "
  "(Null-Ausbuchung bei Altfällen ist normal).")

d=api("POST","/api/dashboard",{"name":"8 · Datenqualität & Betrieb","collection_id":COLL,
  "description":"Vertrauens-Cockpit: Abdeckung je Dimension, ETL-Laufstatus, Aktualität "
                "und automatische Anomalie-Prüfungen. Fundament für belastbare Zahlen."})
did=d["id"]; print("dashboard",did,d.get("name"))
dcs=[
 {"id":-1,"card_id":cA,"col":0,"row":0,"size_x":24,"size_y":8,"parameter_mappings":[],"visualization_settings":{}},
 {"id":-2,"card_id":cD,"col":0,"row":8,"size_x":24,"size_y":6,"parameter_mappings":[],"visualization_settings":{}},
 {"id":-3,"card_id":cB,"col":0,"row":14,"size_x":12,"size_y":8,"parameter_mappings":[],"visualization_settings":{}},
 {"id":-4,"card_id":cC,"col":12,"row":14,"size_x":12,"size_y":8,"parameter_mappings":[],"visualization_settings":{}},
]
api("PUT","/api/dashboard/%d"%did,{"dashcards":dcs})
print("cockpit fertig, dashboard",did)
