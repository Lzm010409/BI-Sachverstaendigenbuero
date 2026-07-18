#!/usr/bin/env python3
"""NACH dem Deploy (sql/039 + sql/040 + Flow-Extractor) ausführen: hängt Dashboard 9
die beiden Stage-Cards an, die raw-Felder über Views lesen (gehen erst nach Deploy):
  1. v_stage_offen        (Stufe 1) — offene Fälle je AKTUELLEM Stage + Alter
  2. v_stage_verweildauer (Stufe 2) — Ø/Median Verweildauer JE Stage (Changelog)
Jede Card wird nur angehängt, wenn ihre View existiert (Vorabprüfung)."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5; DASH=9

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
def make_card(name,sql,viz,desc):
    r=api("POST","/api/card",{"name":name,"display":"table","dataset_query":q(sql),
          "visualization_settings":viz,"collection_id":COLL,"description":desc})
    print("card",r.get("id"),name[:45]); return r["id"]
def append(card_id,size_y=6):
    d=api("GET","/api/dashboard/%d"%DASH); dcs=[]; bottom=0
    for i,dc in enumerate(d.get("dashcards",[])):
        if dc.get("card_id")==card_id:  # schon dran → nicht doppeln
            print("card",card_id,"schon auf Dashboard, übersprungen"); return
        dcs.append({"id":-(i+1),"card_id":dc.get("card_id"),"col":dc["col"],"row":dc["row"],
                    "size_x":dc["size_x"],"size_y":dc["size_y"],
                    "parameter_mappings":dc.get("parameter_mappings",[]),
                    "visualization_settings":dc.get("visualization_settings",{})})
        bottom=max(bottom,dc["row"]+dc["size_y"])
    dcs.append({"id":-(len(dcs)+1),"card_id":card_id,"col":0,"row":bottom,"size_x":24,"size_y":size_y,
                "parameter_mappings":[],"visualization_settings":{}})
    api("PUT","/api/dashboard/%d"%DASH,{"dashcards":dcs}); print("  -> angehängt bei row",bottom)

# 1) wo klemmt es (Stufe 1)
if view_ok("marts.v_stage_offen"):
    c=make_card("Offene Fälle je Stage + Alterung (wo klemmt es)","""
SELECT stage AS "Stage", anzahl_offen AS "Offene Fälle",
       median_alter_tage AS "Median Alter (Tage)", schnitt_alter_tage AS "Ø Alter (Tage)",
       aelter_30_tage AS "davon > 30 Tage"
FROM marts.v_stage_offen ORDER BY order_nr""",
      {"table.column_formatting":[{"columns":["davon > 30 Tage"],"type":"single",
        "operator":">","value":0,"color":"#ED6E6E","highlight_row":False}]},
      "LF6 Stufe 1 — offene (nicht bezahlte) Fälle je AKTUELLEM Stage und wie lange "
      "sie dort liegen. Hoher Bestand + hohes Alter = Engpass. Pipedrive liefert hier "
      "nur den letzten Stage-Wechsel → Alter ab diesem Wechsel.")
    append(c,6)
else:
    print("v_stage_offen fehlt — sql/039 noch nicht deployt, übersprungen.")

# 2) Verweildauer je Stage (Stufe 2, Changelog)
if view_ok("marts.v_stage_verweildauer"):
    c=make_card("Verweildauer je Stage — Median/Ø (Stufe 2, Changelog)","""
SELECT stage AS "Stage", anzahl_segmente AS "Segmente", davon_offen AS "davon offen",
       median_tage AS "Median Tage", schnitt_tage AS "Ø Tage", p90_tage AS "P90 Tage"
FROM marts.v_stage_verweildauer ORDER BY order_nr""",{},
      "LF6 Stufe 2 — exakte Verweildauer JE Stage aus der Pipedrive-Stage-Historie "
      "(Changelog). Zeigt, in welchem Bearbeitungsschritt die Zeit wirklich liegt. "
      "Median statt Ø (Langläufer/Klage verzerren den Schnitt).")
    append(c,6)
else:
    print("v_stage_verweildauer fehlt — sql/040 + Flow-Extractor noch nicht gelaufen, übersprungen.")

print("fertig.")
