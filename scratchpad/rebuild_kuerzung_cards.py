#!/usr/bin/env python3
"""Stellt die Kürzung/Durchsetzung-Cards auf die ZAHLUNGSBASIERTE Quelle um
(marts.v_durchsetzung_zahlung*). Dashboard 1 (id 2) + Anwalt-Cards in Dashboard 8 (id 8).
Löst die dünnen OCR-Cards ab (183 belastbare Fälle statt 12-18)."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=60)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:200]}
def q(s): return {"database":DB,"type":"native","native":{"query":s}}
def put_card(cid,name,display,sql,viz,desc):
    r=api("PUT","/api/card/%d"%cid,{"name":name,"display":display,"dataset_query":q(sql),"visualization_settings":viz,"description":desc})
    print("card",cid,"->",r.get("display"),r.get("name","?")[:50])

# ============ Dashboard 1 (id 2): Durchsetzung & Kürzungen — zahlungsbasiert ====
put_card(41,"Kürzung & Durchsetzung je Versicherer (zahlungsbasiert)","table",
    """SELECT versicherer AS "Versicherer", anzahl_faelle AS "Fälle (n)",
       round(summe_kuerzung,2) AS "Σ Kürzung €", round(summe_ausbuchung,2) AS "Σ Ausbuchung €",
       round(100*durchsetzungsquote,1) AS "Durchgesetzt %"
FROM marts.v_durchsetzung_zahlung_je_versicherer ORDER BY summe_kuerzung DESC""",{},
    "LF2/3 — Kürzung = Rechnung − erste Zahlung (sevDesk-Buchungen); Ausbuchung aus Konto "
    "'Ausgebuchte Rechnungen'; Durchsetzung = 1 − Ausbuchung/Kürzung. Nur won, ohne USt-"
    "Einbehalt & Haftungsquote. 183 belastbare Fälle. (Versicherer-Namen noch dubliziert.)")

put_card(42,"Durchsetzungsquote je Versicherer (n≥3)","row",
    """SELECT versicherer AS versicherer, round(100*durchsetzungsquote,1) AS durchgesetzt_pct
FROM marts.v_durchsetzung_zahlung_je_versicherer WHERE anzahl_faelle>=3 ORDER BY durchgesetzt_pct DESC""",
    {"graph.dimensions":["versicherer"],"graph.metrics":["durchgesetzt_pct"],
     "graph.x_axis.title_text":"Versicherer","graph.y_axis.title_text":"Durchgesetzt %"},
    "LF3 — Durchsetzungsquote je Versicherer, nur ≥3 Fälle (statistisch belastbar).")

put_card(43,"Durchsetzung je Fall (zahlungsbasiert)","table",
    """SELECT aktenzeichen AS "Aktenzeichen", versicherer AS "Versicherer", anwalt AS "Anwalt/Kanzlei",
       rechnung_brutto AS "Rechnung €", erste_zahlung AS "Erste Zahlung €",
       kuerzung AS "Kürzung €", ausgebucht AS "Ausgebucht €",
       round(100*durchsetzungsquote,1) AS "Durchgesetzt %", erste_zahlung_datum::date AS "1. Zahlung"
FROM marts.v_durchsetzung_zahlung ORDER BY kuerzung DESC""",{},
    "LF3 — jeder abgeschlossene Kürzungsfall mit Zahlungsverlauf. Kürzung/Ausbuchung/Quote aus "
    "den sevDesk-Buchungen. 183 Fälle.")

put_card(44,"Kürzung je Grund (LF2)","row",
    """SELECT kuerzungsgrund AS grund, round(summe_kuerzung,2) AS summe_kuerzung
FROM marts.v_kuerzung_zahlung_je_grund ORDER BY summe_kuerzung DESC""",
    {"graph.dimensions":["grund"],"graph.metrics":["summe_kuerzung"],
     "graph.x_axis.title_text":"Kürzungsgrund","graph.y_axis.title_text":"Σ Kürzung €"},
    "LF2 — Kürzung je Grund. Grober Grund aus Pipedrive-Ausbuchungsgrund; '(offen)' = kein "
    "Ausbuchungsgrund (voll durchgesetzt). Detail-Grund aus den Schreiben füllt sich künftig.")

# Layout Dashboard 1 neu
d1=[(41,0,0,24,8),(42,0,8,12,7),(44,12,8,12,7),(43,0,15,24,9)]
api("PUT","/api/dashboard/2",{"dashcards":[{"id":-(i+1),"card_id":c,"col":col,"row":row,"size_x":sx,"size_y":sy,"parameter_mappings":[],"visualization_settings":{}} for i,(c,col,row,sx,sy) in enumerate(d1)]})
print("Dashboard 2 re-layout ok")

# ============ Dashboard 8 (id 8): Anwalt-Kürzungscards — zahlungsbasiert =========
put_card(64,"Kürzung & Durchsetzung je Anwalt (zahlungsbasiert)","table",
    """SELECT anwalt AS "Anwalt / Kanzlei", anzahl_faelle AS "Fälle (n)",
       round(summe_kuerzung,2) AS "Σ Kürzung €", round(summe_ausbuchung,2) AS "Σ Ausbuchung €",
       round(100*durchsetzungsquote,1) AS "Durchgesetzt %"
FROM marts.v_durchsetzung_zahlung_je_anwalt ORDER BY summe_kuerzung DESC""",{},
    "LF2/3 je Anwalt — zahlungsbasiert. RA Busch führt (68 Fälle). '(kein Anwalt erfasst)' = "
    "Fälle ohne Anwalt im Deal.")

put_card(65,"Kürzung je Anwalt × Versicherer (zahlungsbasiert)","table",
    """SELECT COALESCE(anwalt,'(kein Anwalt)') AS "Anwalt / Kanzlei", versicherer AS "Versicherer",
       count(*) AS "Fälle", round(sum(kuerzung),2) AS "Σ Kürzung €", round(sum(ausgebucht),2) AS "Σ Ausbuchung €"
FROM marts.v_durchsetzung_zahlung GROUP BY 1,2 ORDER BY sum(kuerzung) DESC LIMIT 40""",{},
    "LF2 — welche Kanzlei gegen welchen Versicherer, wie viel Kürzung. Zahlungsbasiert.")

put_card(66,"Durchsetzungsquote je Anwalt × Versicherer (zahlungsbasiert)","table",
    """SELECT COALESCE(anwalt,'(kein Anwalt)') AS "Anwalt / Kanzlei", versicherer AS "Versicherer",
       count(*) AS "Fälle", round(sum(kuerzung),2) AS "Σ Kürzung €", round(sum(ausgebucht),2) AS "Σ Ausbuchung €",
       round(100*(1-sum(ausgebucht)/NULLIF(sum(kuerzung),0)),1) AS "Durchgesetzt %"
FROM marts.v_durchsetzung_zahlung GROUP BY 1,2 ORDER BY sum(kuerzung) DESC LIMIT 40""",{},
    "LF3 — Durchsetzungsquote je Kanzlei×Versicherer, zahlungsbasiert.")

# Dashboard 8 Layout + Banner aktualisieren
BANNER=("✅ **Kürzung & Durchsetzung sind jetzt ZAHLUNGSBASIERT** (sevDesk-Buchungen, **183 Fälle**): "
        "Kürzung = Rechnung − erste Zahlung · Ausbuchung = Konto Ausgebuchte Rechnungen · "
        "Durchsetzung = 1 − Ausbuchung/Kürzung. Zuverlässig & datiert, ohne USt-Einbehalt/Haftungsquote. "
        "Grund aus Pipedrive-Ausbuchungsgrund (Detail-Grund aus den Schreiben füllt sich künftig).")
d8=[{"id":-1,"card_id":61,"col":0,"row":0,"size_x":24,"size_y":8,"parameter_mappings":[],"visualization_settings":{}},
    {"id":-2,"card_id":62,"col":0,"row":8,"size_x":12,"size_y":7,"parameter_mappings":[],"visualization_settings":{}},
    {"id":-3,"card_id":63,"col":12,"row":8,"size_x":12,"size_y":7,"parameter_mappings":[],"visualization_settings":{}},
    {"id":-4,"card_id":None,"col":0,"row":15,"size_x":24,"size_y":2,"parameter_mappings":[],"visualization_settings":{"text":BANNER,"text.align_vertical":"middle"}},
    {"id":-5,"card_id":64,"col":0,"row":17,"size_x":24,"size_y":8,"parameter_mappings":[],"visualization_settings":{}},
    {"id":-6,"card_id":65,"col":0,"row":25,"size_x":12,"size_y":8,"parameter_mappings":[],"visualization_settings":{}},
    {"id":-7,"card_id":66,"col":12,"row":25,"size_x":12,"size_y":8,"parameter_mappings":[],"visualization_settings":{}}]
api("PUT","/api/dashboard/8",{"dashcards":d8})
print("Dashboard 8 re-layout + Banner ok")
