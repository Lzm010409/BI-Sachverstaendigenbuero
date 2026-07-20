#!/usr/bin/env python3
"""Stufe C11 — Self-Service-Filter (Vorlage). Interaktives Durchsetzungs-Dashboard mit
Zeitraum-, Versicherer- und Anwalt-Filter (native Field-Filter auf v_durchsetzung_zahlung,
Feld-IDs: erste_zahlung_datum=2040, versicherer=2030, anwalt=2031). Filter sind OPTIONAL
([[ ... ]]) → Cards zeigen ohne Auswahl den Gesamtstand. Bestehende Cards bleiben unberührt."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=90)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:300]}

TT={
 "zeitraum":{"id":"tt_zeitraum","name":"zeitraum","display-name":"Zeitraum","type":"dimension",
             "dimension":["field",2040,None],"widget-type":"date/range"},
 "versicherer":{"id":"tt_versicherer","name":"versicherer","display-name":"Versicherer","type":"dimension",
             "dimension":["field",2030,None],"widget-type":"string/="},
 "anwalt":{"id":"tt_anwalt","name":"anwalt","display-name":"Anwalt","type":"dimension",
             "dimension":["field",2031,None],"widget-type":"string/="},
}
WHERE="WHERE 1=1 [[AND {{zeitraum}}]] [[AND {{versicherer}}]] [[AND {{anwalt}}]]"

def card(name,display,sql,viz,desc):
    dq={"database":DB,"type":"native","native":{"query":sql,"template-tags":TT}}
    r=api("POST","/api/card",{"name":name,"display":display,"dataset_query":dq,
          "visualization_settings":viz,"collection_id":COLL,"description":desc})
    print("card",r.get("id"),name[:40]); return r["id"]

c1=card("Durchsetzung — Kennzahlen (gefiltert)","table",f"""
SELECT count(*) AS "Fälle", round(sum(kuerzung)) AS "Σ Kürzung €",
  round(sum(kuerzung-ausgebucht)) AS "Σ durchgesetzt €",
  round(sum(ausgebucht)) AS "Σ verloren €",
  round(100*(1-sum(ausgebucht)/NULLIF(sum(kuerzung),0)),1) AS "Durchsetzung %"
FROM marts.v_durchsetzung_zahlung {WHERE}""",{},
  "Durchsetzungs-Kennzahlen, gefiltert nach Zeitraum/Versicherer/Anwalt. Ohne Filter = "
  "Gesamtstand. Durchsetzung % = 1 − Σ Ausbuchung / Σ Kürzung.")

c2=card("Durchsetzung je Versicherer (gefiltert)","table",f"""
SELECT versicherer AS "Versicherer", count(*) AS "Fälle",
  round(sum(kuerzung)) AS "Σ Kürzung €",
  round(100*(1-sum(ausgebucht)/NULLIF(sum(kuerzung),0)),1) AS "Durchsetzung %"
FROM marts.v_durchsetzung_zahlung {WHERE}
GROUP BY 1 ORDER BY 3 DESC""",
  {"table.column_formatting":[{"columns":["Durchsetzung %"],"type":"range","colors":["#ED6E6E","#84C868"]}]},
  "Durchsetzungsquote je Versicherer, gefiltert. Farbskala rot→grün.")

c3=card("Durchsetzung je Anwalt (gefiltert)","table",f"""
SELECT COALESCE(anwalt,'(kein Anwalt)') AS "Anwalt", count(*) AS "Fälle",
  round(sum(kuerzung)) AS "Σ Kürzung €",
  round(100*(1-sum(ausgebucht)/NULLIF(sum(kuerzung),0)),1) AS "Durchsetzung %"
FROM marts.v_durchsetzung_zahlung {WHERE}
GROUP BY 1 ORDER BY 3 DESC""",{},
  "Durchsetzungsquote je Anwalt/Kanzlei, gefiltert.")

PARAMS=[
 {"id":"p_zeit","name":"Zeitraum","slug":"zeitraum","type":"date/range","sectionId":"date"},
 {"id":"p_vers","name":"Versicherer","slug":"versicherer","type":"string/=","sectionId":"string"},
 {"id":"p_anw","name":"Anwalt","slug":"anwalt","type":"string/=","sectionId":"string"},
]
def maps(cid):
    return [
     {"parameter_id":"p_zeit","card_id":cid,"target":["dimension",["template-tag","zeitraum"]]},
     {"parameter_id":"p_vers","card_id":cid,"target":["dimension",["template-tag","versicherer"]]},
     {"parameter_id":"p_anw","card_id":cid,"target":["dimension",["template-tag","anwalt"]]},
    ]

d=api("POST","/api/dashboard",{"name":"1a · Durchsetzung interaktiv (Filter)","collection_id":COLL,
  "description":"Selbstbedienung: Durchsetzung nach Zeitraum, Versicherer und Anwalt filtern. "
                "Vorlage für Self-Service-Filter (Stufe C11)."})
did=d["id"]; print("dashboard",did,d.get("name"))
dcs=[
 {"id":-1,"card_id":c1,"col":0,"row":0,"size_x":24,"size_y":4,"parameter_mappings":maps(c1),"visualization_settings":{}},
 {"id":-2,"card_id":c2,"col":0,"row":4,"size_x":12,"size_y":8,"parameter_mappings":maps(c2),"visualization_settings":{}},
 {"id":-3,"card_id":c3,"col":12,"row":4,"size_x":12,"size_y":8,"parameter_mappings":maps(c3),"visualization_settings":{}},
]
api("PUT","/api/dashboard/%d"%did,{"dashcards":dcs,"parameters":PARAMS})
print("interaktives dashboard fertig:",did)
