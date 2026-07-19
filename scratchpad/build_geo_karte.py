#!/usr/bin/env python3
"""NACH dem Deploy (sql/042+043 + load-plz-geo + Personen-Reextraktion) ausführen:
Dashboard 5 um geografische Karte + Heatmap-Tabelle je 4-stelliger PLZ erweitern.
Liest marts.v_geo_je_plz4 (Lat/Lon aus core.dim_plz_geo, ≥3 Fälle). Namens-idempotent."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5; DASH=5

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=90)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:300]}
def q(s): return {"database":DB,"type":"native","native":{"query":s}}
def view_ok(view):
    r=api("POST","/api/dataset",q("SELECT 1 FROM %s LIMIT 1"%view))
    return bool(r.get("data",{}).get("rows") is not None and "error" not in r)
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
def append(cid,size_y=8):
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

if not view_ok("marts.v_geo_je_plz4"):
    print("v_geo_je_plz4 fehlt/leer — sql/042+043 + Deploy + Reextraktion noch nicht durch. Abbruch.")
    raise SystemExit(0)

# 1) Pin-Karte: ein Punkt je plz4 am Centroid, Umsatz/Fälle im Hover
cM=card("Einzugsgebiet-Karte je PLZ-4 (Fälle & Umsatz)","map","""
SELECT plz4 AS "PLZ-4", lat AS "lat", lon AS "lon",
       anzahl_faelle AS "Fälle", round(summe_fakturiert_brutto) AS "Umsatz €"
FROM marts.v_geo_je_plz4
WHERE lat IS NOT NULL AND lon IS NOT NULL
ORDER BY anzahl_faelle DESC""",
  {"map.type":"pin","map.latitude_column":"lat","map.longitude_column":"lon"},
  "LF7 — geografische Verteilung der (bezahlten) Fälle je 4-stelligem PLZ-Gebiet. "
  "Ein Punkt je PLZ-4 am Gebiets-Centroid (Referenz core.dim_plz_geo). Hover zeigt "
  "Fälle und Umsatz. Nur Gebiete mit ≥3 Fällen (DSGVO). Zeigt, wo räumlich der "
  "Schwerpunkt des Einzugsgebiets liegt.")
if cM: append(cM,10)

# 2) Heatmap-Tabelle: welche Kennzahl sticht je plz4 heraus (farbcodiert)
cH=card("Heatmap je PLZ-4 — welche Kennzahl sticht heraus","table","""
SELECT plz4 AS "PLZ-4", anzahl_faelle AS "Fälle",
       round(summe_fakturiert_brutto) AS "Umsatz €",
       round(schnitt_fakturiert_brutto) AS "Ø Honorar €",
       round(schnitt_schadenhoehe_brutto) AS "Ø Schadenhöhe €",
       totalschaden_quote_pct AS "Totalschaden %"
FROM marts.v_geo_je_plz4
ORDER BY anzahl_faelle DESC""",
  {"table.column_formatting":[
     {"columns":["Fälle"],"type":"range","colors":["#FFFFFF","#509EE3"]},
     {"columns":["Umsatz €"],"type":"range","colors":["#FFFFFF","#88BF4D"]},
     {"columns":["Ø Schadenhöhe €"],"type":"range","colors":["#FFFFFF","#F9CF48"]},
     {"columns":["Totalschaden %"],"type":"range","colors":["#FFFFFF","#ED6E6E"]}]},
  "LF7 — Heatmap: je 4-stelligem PLZ-Gebiet farbcodiert, welche Kennzahl heraussticht "
  "(Fallzahl, Umsatz, Ø Schadenhöhe, Totalschaden-Quote). Dunkler = höher. So sieht man "
  "auf einen Blick, welche Region z. B. viele Totalschäden oder hohe Schadenhöhen bringt. "
  "Nur Gebiete mit ≥3 Fällen (DSGVO).")
if cH: append(cH,8)
print("fertig.")
