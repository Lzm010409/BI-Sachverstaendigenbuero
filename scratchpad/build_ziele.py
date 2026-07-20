#!/usr/bin/env python3
"""Stufe C10 — Ziele & Soll-Ist. Eine Card auf dem Management-Cockpit vergleicht die
Kern-KPIs mit Zielwerten (Ampel). Zielwerte hier als Defaults, jederzeit anpassbar."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5; DASH=11

# --- Zielwerte (editierbar) ---
Z_DURCHSETZUNG=85      # %  (Ist ~82,6)
Z_UMSATZ=45000         # €/Monat (Vormonat; Ist-Median ~35k, Schnitt ~47k)
Z_DURCHLAUF=45         # Tage Obergrenze (Ist ~52)
Z_KONFORM=85           # %  (Ist ~77)

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=90)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:300]}
def q(s): return {"database":DB,"type":"native","native":{"query":s}}

sql=f"""
WITH ist AS (
  SELECT
    (SELECT round(100*(1-sum(ausgebucht)/NULLIF(sum(kuerzung),0)),1) FROM marts.v_durchsetzung_zahlung) AS durchsetzung,
    (SELECT round(sum(deal_value_brutto)) FROM core.fact_ausbuchung
       WHERE won_time >= date_trunc('month',now())-interval '1 month' AND won_time < date_trunc('month',now())) AS umsatz_vm,
    (SELECT median_tage FROM marts.v_durchlaufzeit) AS durchlauf,
    (SELECT round(100.0*count(*) FILTER (WHERE befund='konform')/NULLIF(count(*),0),1) FROM marts.v_honorar_konformitaet) AS konform
),
z(kennzahl, ist, ziel, richtung, ord) AS (
  SELECT 'Durchsetzungsquote %',        (SELECT durchsetzung FROM ist), {Z_DURCHSETZUNG}::numeric, 'hoch', 1
  UNION ALL SELECT 'Monatsumsatz € (Vormonat)', (SELECT umsatz_vm FROM ist),   {Z_UMSATZ}::numeric,       'hoch', 2
  UNION ALL SELECT 'Median Durchlaufzeit (Tage)',(SELECT durchlauf FROM ist),  {Z_DURCHLAUF}::numeric,    'niedrig', 3
  UNION ALL SELECT 'Honorar-Konformität %',     (SELECT konform FROM ist),     {Z_KONFORM}::numeric,      'hoch', 4
)
SELECT kennzahl AS "Kennzahl", ist AS "Ist", ziel AS "Ziel",
  CASE WHEN richtung='hoch'   THEN round(100.0*ist/NULLIF(ziel,0))
       ELSE round(100.0*ziel/NULLIF(ist,0)) END AS "Zielerreichung %",
  CASE WHEN richtung='hoch'   AND ist>=ziel THEN '✅ erreicht'
       WHEN richtung='niedrig' AND ist<=ziel THEN '✅ erreicht'
       WHEN richtung='hoch'   AND ist>=0.9*ziel THEN '🟡 nah dran'
       WHEN richtung='niedrig' AND ist<=1.1*ziel THEN '🟡 nah dran'
       ELSE '🔴 unter Ziel' END AS "Status"
FROM z ORDER BY ord"""

r=api("POST","/api/card",{"name":"Ziele: Soll-Ist (Zielerreichung)","display":"table",
      "dataset_query":q(sql),
      "visualization_settings":{"table.column_formatting":[
        {"columns":["Zielerreichung %"],"type":"range","colors":["#ED6E6E","#FFFFFF","#84C868"],
         "min_type":"custom","min_value":50,"max_type":"custom","max_value":110}]},
      "collection_id":COLL,
      "description":"Soll-Ist der Kern-KPIs gegen Zielwerte (Durchsetzung 85 %, Monatsumsatz "
      "45.000 €, Durchlaufzeit ≤45 T, Konformität 85 %). Zielwerte sind Defaults und "
      "jederzeit anpassbar. 'Zielerreichung %' >100 = übertroffen."})
cid=r["id"]; print("card",cid,"Ziele Soll-Ist")

# unten ans Cockpit haengen (unter die KPI-Kacheln, row 12)
d=api("GET","/api/dashboard/%d"%DASH); dcs=[]; bottom=0
for i,dc in enumerate(d.get("dashcards",[])):
    dcs.append({"id":-(i+1),"card_id":dc.get("card_id"),"col":dc["col"],"row":dc["row"],
                "size_x":dc["size_x"],"size_y":dc["size_y"],
                "parameter_mappings":dc.get("parameter_mappings",[]),
                "visualization_settings":dc.get("visualization_settings",{})})
    bottom=max(bottom,dc["row"]+dc["size_y"])
dcs.append({"id":-(len(dcs)+1),"card_id":cid,"col":0,"row":bottom,"size_x":24,"size_y":6,
            "parameter_mappings":[],"visualization_settings":{}})
api("PUT","/api/dashboard/%d"%DASH,{"dashcards":dcs})
print("Ziele-Card ans Cockpit angehaengt, row",bottom)
