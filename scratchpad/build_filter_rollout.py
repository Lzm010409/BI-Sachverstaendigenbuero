#!/usr/bin/env python3
"""Stufe C11 Roll-out — Zeitraum-Filter auf Umsatz (4), Durchlaufzeit (9), Geo (5).
Je Dashboard eine zeitraum-gefilterte Card (native Field-Filter auf won_time) + der
Zeitraum-Parameter. Bestehende Cards/Parameter bleiben erhalten."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=90)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:300]}

def zt(field_id):  # Zeitraum-Template-Tag auf ein Datumsfeld
    return {"zeitraum":{"id":"tt_zeitraum","name":"zeitraum","display-name":"Zeitraum",
            "type":"dimension","dimension":["field",field_id,None],"widget-type":"date/range"}}

def make_card(name,display,sql,field_id,viz,desc):
    dq={"database":DB,"type":"native","native":{"query":sql,"template-tags":zt(field_id)}}
    r=api("POST","/api/card",{"name":name,"display":display,"dataset_query":dq,
          "visualization_settings":viz,"collection_id":COLL,"description":desc})
    print("card",r.get("id"),name[:42]); return r["id"]

def rollout(dash_id, card_id, size_y=6):
    d=api("GET","/api/dashboard/%d"%dash_id)
    dcs=[]; bottom=0
    for i,dc in enumerate(d.get("dashcards",[])):
        dcs.append({"id":-(i+1),"card_id":dc.get("card_id"),"col":dc["col"],"row":dc["row"],
                    "size_x":dc["size_x"],"size_y":dc["size_y"],
                    "parameter_mappings":dc.get("parameter_mappings",[]),
                    "visualization_settings":dc.get("visualization_settings",{})})
        bottom=max(bottom,dc["row"]+dc["size_y"])
    dcs.append({"id":-(len(dcs)+1),"card_id":card_id,"col":0,"row":bottom,"size_x":24,"size_y":size_y,
                "parameter_mappings":[{"parameter_id":"p_zeit","card_id":card_id,
                    "target":["dimension",["template-tag","zeitraum"]]}],
                "visualization_settings":{}})
    params=[p for p in d.get("parameters",[]) if p.get("id")!="p_zeit"]
    params.append({"id":"p_zeit","name":"Zeitraum","slug":"zeitraum","type":"date/range","sectionId":"date"})
    api("PUT","/api/dashboard/%d"%dash_id,{"dashcards":dcs,"parameters":params})
    print("  -> dashboard",dash_id,"Zeitraum-Filter + Card row",bottom)

# Umsatz & Zahlungsausfaelle (id 4)
c=make_card("Umsatz & Forderungsverlust (Zeitraum-gefiltert)","table",
  """SELECT count(*) AS "Fälle",
       round(sum(deal_value_brutto)) AS "Umsatz € brutto",
       round(sum(ausgebucht_betrag) FILTER (WHERE ausgebucht_betrag>0)) AS "Forderungsverlust €"
     FROM core.fact_ausbuchung WHERE won_time IS NOT NULL [[AND {{zeitraum}}]]""",1800,{},
  "LF5 — Umsatz, Fallzahl und Forderungsverlust im oben gewählten Zeitraum (Filter wirkt "
  "auf diese Card). Ohne Auswahl = Gesamtzeitraum.")
rollout(4,c,4)

# Durchlaufzeiten (id 9)
c=make_card("Durchlaufzeit-Kennzahlen (Zeitraum-gefiltert)","table",
  """SELECT count(*) AS "Fälle (won)",
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (won_time-add_time))/86400.0)::numeric,1) AS "Median Tage",
       round(avg(EXTRACT(EPOCH FROM (won_time-add_time))/86400.0)::numeric,1) AS "Ø Tage"
     FROM core.fact_ausbuchung WHERE won_time IS NOT NULL AND add_time >= DATE '2024-11-01' [[AND {{zeitraum}}]]""",1800,{},
  "LF6 — Median-/Ø-Durchlaufzeit im gewählten Zeitraum (nach won_time gefiltert).")
rollout(9,c,4)

# Geo (id 5)
c=make_card("Umsatz je PLZ-Gebiet (Zeitraum-gefiltert)","table",
  """SELECT plz_gebiet AS "PLZ-Gebiet", count(*) AS "Fälle", round(sum(fakturiert_brutto)) AS "Umsatz €"
     FROM marts.v_fall_geo WHERE plz_gebiet IS NOT NULL [[AND {{zeitraum}}]]
     GROUP BY 1 ORDER BY 3 DESC""",1998,{},
  "LF7 — Umsatz/Fälle je 2-stelligem PLZ-Gebiet im gewählten Zeitraum (nach won_time).")
rollout(5,c,7)
print("Roll-out fertig.")
