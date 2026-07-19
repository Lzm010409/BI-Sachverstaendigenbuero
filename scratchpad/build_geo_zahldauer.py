#!/usr/bin/env python3
"""Dashboard 5 (Geo, LF7) erweitern: GEO x Zahldauer + GEO x Kürzung je PLZ-Gebiet.
Kernfrage des Inhabers: regulieren Versicherer in manchen Regionen langsamer / kürzen
mehr? Aggregiert auf 2-stelliges PLZ-Gebiet, Mindestfallzahl >=5 (DSGVO + Statistik),
Fallzahl je Zeile sichtbar. Inline-SQL -> sofort live."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5; DASH=5

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=90)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:300]}
def q(s): return {"database":DB,"type":"native","native":{"query":s}}
def on_dash(name):
    d=api("GET","/api/dashboard/%d"%DASH)
    for dc in d.get("dashcards",[]):
        if (dc.get("card") or {}).get("name")==name: return True
    return False
def card(name,display,sql,viz,desc):
    if on_dash(name): print("schon da:",name[:40]); return None
    r=api("POST","/api/card",{"name":name,"display":display,"dataset_query":q(sql),
          "visualization_settings":viz,"collection_id":COLL,"description":desc})
    print("card",r.get("id"),name[:40]); return r["id"]
def append(cid,size_y=7):
    d=api("GET","/api/dashboard/%d"%DASH); dcs=[]; bottom=0
    for i,dc in enumerate(d.get("dashcards",[])):
        dcs.append({"id":-(i+1),"card_id":dc.get("card_id"),"col":dc["col"],"row":dc["row"],
                    "size_x":dc["size_x"],"size_y":dc["size_y"],
                    "parameter_mappings":dc.get("parameter_mappings",[]),
                    "visualization_settings":dc.get("visualization_settings",{})})
        bottom=max(bottom,dc["row"]+dc["size_y"])
    dcs.append({"id":-(len(dcs)+1),"card_id":cid,"col":0,"row":bottom,"size_x":24,"size_y":size_y,
                "parameter_mappings":[],"visualization_settings":{}})
    api("PUT","/api/dashboard/%d"%DASH,{"dashcards":dcs}); print("  -> row",bottom)

REGION=("CASE g.plz_gebiet WHEN '41' THEN '41 · Neuss/MG' WHEN '40' THEN '40 · Düsseldorf' "
        "WHEN '47' THEN '47 · Krefeld/Duisburg' WHEN '52' THEN '52 · Aachen' "
        "WHEN '50' THEN '50 · Köln' WHEN '44' THEN '44 · Dortmund' ELSE g.plz_gebiet END")

BASECTE=f"""
WITH rd AS (SELECT aktenzeichen, min(rechnungsdatum) rechnungsdatum FROM core.fact_rechnungsposition GROUP BY 1),
agg AS (
  SELECT {REGION} AS gebiet,
    count(*) FILTER (WHERE dz.kuerzung IS NOT NULL) AS n,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (dz.erste_zahlung_datum-rd.rechnungsdatum))/86400.0)
      FILTER (WHERE dz.erste_zahlung_datum >= rd.rechnungsdatum) AS median_zahldauer,
    avg(EXTRACT(EPOCH FROM (dz.erste_zahlung_datum-rd.rechnungsdatum))/86400.0)
      FILTER (WHERE dz.erste_zahlung_datum >= rd.rechnungsdatum) AS schnitt_zahldauer,
    avg(dz.kuerzung) AS schnitt_kuerzung,
    100.0*sum(dz.kuerzung) FILTER (WHERE dz.kuerzung>0)/NULLIF(sum(dz.rechnung_brutto),0) AS kuerzquote,
    avg(dz.durchsetzungsquote) AS durchsetzung
  FROM marts.v_fall_geo g
  JOIN marts.v_durchsetzung_zahlung dz USING(aktenzeichen)
  LEFT JOIN rd USING(aktenzeichen)
  WHERE g.plz_gebiet IS NOT NULL AND g.plz_gebiet <> ''
  GROUP BY 1
)
"""

# Card A: Tabelle Zahldauer + Regulierung je PLZ-Gebiet
cA=card("Zahldauer & Regulierung je PLZ-Gebiet (≥5 Fälle)","table", BASECTE+"""
SELECT gebiet AS "PLZ-Gebiet", n AS "Fälle",
  round(median_zahldauer::numeric,1) AS "Median Zahldauer (Tage)",
  round(schnitt_zahldauer::numeric,1) AS "Ø Zahldauer (Tage)",
  round(schnitt_kuerzung::numeric) AS "Ø Kürzung €",
  round(durchsetzung::numeric*100,1) AS "Durchsetzung %"
FROM agg WHERE n >= 5 ORDER BY n DESC""",
  {"table.column_formatting":[
     {"columns":["Median Zahldauer (Tage)"],"type":"range","colors":["#84C868","#ED6E6E"]},
     {"columns":["Durchsetzung %"],"type":"range","colors":["#ED6E6E","#84C868"]}]},
  "LF7 × Zahlungsverhalten — je PLZ-Gebiet des Geschädigten: wie lange bis zur ersten "
  "Zahlung (Rechnungsdatum → erste_zahlung_datum) und wie stark wird reguliert. "
  "Beantwortet 'regulieren Versicherer in manchen Regionen langsamer / kürzen mehr'. "
  "WICHTIG: bezahlt wird vom Versicherer, nicht vom Geschädigten — das Gebiet ist der "
  "Fall-Ursprung, nicht der Zahler. Nur Gebiete mit ≥5 Fällen (Statistik + DSGVO); "
  "Median ist belastbarer als Ø (Klage-Langläufer verzerren den Schnitt). n = Fälle mit "
  "Zahlungsdaten. Aktuell nur Gebiet 41 (n≈78) solide, 40/47 (n≈12) indikativ.")
if cA: append(cA,6)

# Card B: Balken Median-Zahldauer je Gebiet (visuell)
cB=card("Median-Zahldauer je PLZ-Gebiet (≥5 Fälle)","bar", BASECTE+"""
SELECT gebiet AS "PLZ-Gebiet", round(median_zahldauer::numeric,1) AS "Median Zahldauer (Tage)"
FROM agg WHERE n >= 5 ORDER BY median_zahldauer DESC NULLS LAST""",
  {"graph.dimensions":["PLZ-Gebiet"],"graph.metrics":["Median Zahldauer (Tage)"],
   "graph.x_axis.title_text":"PLZ-Gebiet","graph.y_axis.title_text":"Tage bis erste Zahlung"},
  "LF7 × Zahlungsverhalten — Median-Tage von Rechnung bis erster Zahlung je PLZ-Gebiet, "
  "höchste zuerst. Langsamste Region oben. Nur Gebiete mit ≥5 Fällen; kleine n (40/47) "
  "nur als Tendenz lesen.")
if cB: append(cB,7)
print("fertig.")
