#!/usr/bin/env python3
"""Fügt zwei gewichtete Cards hinzu: Konfidenz-gewichtete Durchsetzung je Versicherer
(Dashboard 2) und Auftraggeber-Wertigkeit LF4 (Dashboard 7). Inline-SQL → sofort live."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=90)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:200]}
def q(s): return {"database":DB,"type":"native","native":{"query":s}}
def card(name,display,sql,viz,desc):
    r=api("POST","/api/card",{"name":name,"display":display,"dataset_query":q(sql),"visualization_settings":viz,"collection_id":COLL,"description":desc})
    print("card",r.get("id"),name[:45]); return r["id"]

def append_to_dashboard(dash_id, new_card_id, size_y=9):
    d=api("GET","/api/dashboard/%d"%dash_id)
    dcs=[]
    bottom=0
    for i,dc in enumerate(d.get("dashcards",[])):
        dcs.append({"id":-(i+1),"card_id":dc.get("card_id"),"col":dc["col"],"row":dc["row"],
                    "size_x":dc["size_x"],"size_y":dc["size_y"],"parameter_mappings":dc.get("parameter_mappings",[]),
                    "visualization_settings":dc.get("visualization_settings",{})})
        bottom=max(bottom, dc["row"]+dc["size_y"])
    dcs.append({"id":-(len(dcs)+1),"card_id":new_card_id,"col":0,"row":bottom,"size_x":24,"size_y":size_y,
                "parameter_mappings":[],"visualization_settings":{}})
    api("PUT","/api/dashboard/%d"%dash_id,{"dashcards":dcs})
    print("dashboard",dash_id,"-> +1 card at row",bottom)

MU="WITH g AS (SELECT round(1 - sum(ausgebucht)/NULLIF(sum(kuerzung),0),4) mu FROM marts.v_durchsetzung_zahlung)"

# Card A: Durchsetzung je Versicherer, konfidenz-gewichtet
cA=card("Durchsetzungsquote je Versicherer — konfidenz-gewichtet","table", MU+"""
SELECT p.versicherer AS "Versicherer", p.anzahl_faelle AS "Fälle (n)",
       round(100*p.durchsetzungsquote,1) AS "Roh %",
       round(100*(p.anzahl_faelle*p.durchsetzungsquote + 5*g.mu)/(p.anzahl_faelle+5),1) AS "Gewichtet %",
       round(100*g.mu,1) AS "Ø global %"
FROM marts.v_durchsetzung_zahlung_je_versicherer p CROSS JOIN g
ORDER BY (p.anzahl_faelle*p.durchsetzungsquote + 5*g.mu)/(p.anzahl_faelle+5) ASC""",{},
    "Shrinkage (empirical Bayes, k=5): kleine Stichproben zum Gesamtmittel gezogen. "
    "Aufsteigend sortiert = härteste Versicherer zuerst (belastbar trotz kleiner n). "
    "'Roh %' = ungewichtet zum Vergleich.")

# Card B: Auftraggeber-Wertigkeit (LF4)
cB=card("Auftraggeber-Wertigkeit (LF4): realisierter Umsatz × Durchsetzung","table", MU+""",
dg AS (SELECT p.anwalt, (p.anzahl_faelle*p.durchsetzungsquote + 5*(SELECT mu FROM g))/(p.anzahl_faelle+5) dq
       FROM marts.v_durchsetzung_zahlung_je_anwalt p)
SELECT a.anwalt AS "Anwalt / Kanzlei", a.anzahl_faelle AS "Fälle",
       round(a.summe_fakturiert_brutto,0) AS "Umsatz €",
       round(100*(1 - a.summe_forderungsverlust/NULLIF(a.summe_fakturiert_brutto,0)),1) AS "Zahlt zuverl. %",
       round(100*COALESCE(dg.dq, g.mu),1) AS "Durchsetzung gew. %",
       round((a.summe_fakturiert_brutto - a.summe_forderungsverlust)*COALESCE(dg.dq, g.mu),0) AS "Wertigkeit €"
FROM marts.v_anwalt a CROSS JOIN g LEFT JOIN dg ON dg.anwalt=a.anwalt
WHERE a.anwalt<>'(unbekannt)'
ORDER BY (a.summe_fakturiert_brutto - a.summe_forderungsverlust)*COALESCE(dg.dq, g.mu) DESC""",{},
    "LF4 — Wertigkeit = realisierter Umsatz (Umsatz − Forderungsverlust) × konfidenz-"
    "gewichtete Durchsetzung. Ein Blick, welche Kanzlei sich wirklich lohnt.")

append_to_dashboard(2, cA, 9)
append_to_dashboard(7, cB, 9)
