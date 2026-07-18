#!/usr/bin/env python3
"""NACH sql/039-Deploy ausführen: fügt Dashboard 9 die 'wo klemmt es'-Card hinzu
(marts.v_stage_offen — liest raw über die View, geht erst nach Deploy). Idempotent-ish:
prüft vorher, ob die View existiert."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5; DASH=9

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=90)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:300]}
def q(s): return {"database":DB,"type":"native","native":{"query":s}}

# Vorabprüfung: existiert die View?
chk=api("POST","/api/dataset",q("SELECT count(*) FROM marts.v_stage_offen"))
rows=chk.get("data",{}).get("rows")
if not rows:
    print("v_stage_offen noch nicht da (sql/039 nicht deployt?) — abgebrochen.",
          json.dumps(chk)[:200]); raise SystemExit(1)
print("v_stage_offen vorhanden, Zeilen im Ergebnis:", rows[0][0])

sql="""SELECT stage AS "Stage", anzahl_offen AS "Offene Fälle",
       median_alter_tage AS "Median Alter (Tage)", schnitt_alter_tage AS "Ø Alter (Tage)",
       aelter_30_tage AS "davon > 30 Tage"
FROM marts.v_stage_offen ORDER BY order_nr"""
viz={"table.column_formatting":[{"columns":["davon > 30 Tage"],"type":"single",
      "operator":">","value":0,"color":"#ED6E6E","highlight_row":False}]}
r=api("POST","/api/card",{"name":"Offene Fälle je Stage + Alterung (wo klemmt es)",
      "display":"table","dataset_query":q(sql),"visualization_settings":viz,
      "collection_id":COLL,
      "description":"LF6 — offene (nicht bezahlte) Fälle je aktuellem Bearbeitungs-Stage "
      "und wie lange sie dort schon liegen. Hoher Bestand + hohes Alter = Engpass. "
      "Pipedrive liefert nur den letzten Stage-Wechsel → Alter ab diesem Wechsel."})
cid=r["id"]; print("card",cid)

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
print("dashboard",DASH,"-> +stage-offen at row",bottom)
