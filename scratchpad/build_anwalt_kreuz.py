#!/usr/bin/env python3
"""Dashboard: Anwälte × Versicherer — Schaden, Geo, Kürzung, Durchsetzung.
Inline-SQL gegen core.*/marts.*. Anwalt via fact_ausbuchung.anwalt_org_id (aktenzeichen-Join)."""
import json, os, subprocess, sys
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=120)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:300]}
def q(s): return {"database":DB,"type":"native","native":{"query":s}}
def card(name,display,sql,viz,desc):
    r=api("POST","/api/card",{"name":name,"display":display,"dataset_query":q(sql),"visualization_settings":viz,"collection_id":COLL,"description":desc})
    if "id" not in r: print("!! err",name,json.dumps(r)[:300]); sys.exit(1)
    print(f"  card #{r['id']:>3} {display:<6} {name}"); return r["id"]

# 1) Schadenhöhe & Totalschaden je Anwalt (reich)
c1=card("Schadenhöhe & Totalschaden je Anwalt","table","""
SELECT o.name AS "Anwalt / Kanzlei", count(*) AS "Gutachten (n)",
       round(avg(g.schadenhoehe_brutto),0) AS "Ø Schadenhöhe €",
       round(avg(g.reparaturkosten_brutto),0) AS "Ø Reparaturkosten €",
       count(*) FILTER (WHERE g.ist_totalschaden) AS "Totalschäden",
       round(100.0*count(*) FILTER (WHERE g.ist_totalschaden)/count(*),1) AS "TS-Quote %"
FROM core.fact_gutachten g
JOIN core.fact_ausbuchung fa ON fa.aktenzeichen=g.aktenzeichen
JOIN core.dim_organisation o ON o.org_id=fa.anwalt_org_id
GROUP BY 1 ORDER BY count(*) DESC""",{},
    "LF8/10 je Anwalt — Ø Schadenhöhe/Reparaturkosten + Totalschaden-Quote. Coverage 470/592 Gutachten mit Anwalt.")

# 2) Ø Schadenhöhe je Anwalt (Balken, n>=3)
c2=card("Ø Schadenhöhe je Anwalt (n≥3)","row","""
SELECT o.name AS anwalt, round(avg(g.schadenhoehe_brutto),0) AS avg_schadenhoehe
FROM core.fact_gutachten g JOIN core.fact_ausbuchung fa ON fa.aktenzeichen=g.aktenzeichen
JOIN core.dim_organisation o ON o.org_id=fa.anwalt_org_id
GROUP BY 1 HAVING count(*)>=3 ORDER BY avg_schadenhoehe DESC""",
    {"graph.dimensions":["anwalt"],"graph.metrics":["avg_schadenhoehe"],
     "graph.x_axis.title_text":"Anwalt/Kanzlei","graph.y_axis.title_text":"Ø Schadenhöhe brutto €"},
    "Durchschnittliche Schadenhöhe je Anwalt (nur ≥3 Gutachten).")

# 3) PLZ-Gebiet je Anwalt (Kreuz-Tabelle)
c3=card("PLZ-Gebiet je Anwalt (Einzugsgebiet)","table","""
SELECT o.name AS "Anwalt / Kanzlei", geo.plz_gebiet AS "PLZ-Gebiet",
       count(*) AS "Fälle", round(sum(geo.fakturiert_brutto),0) AS "Σ Umsatz €"
FROM marts.v_fall_geo geo JOIN core.fact_ausbuchung fa ON fa.aktenzeichen=geo.aktenzeichen
JOIN core.dim_organisation o ON o.org_id=fa.anwalt_org_id
WHERE geo.plz_gebiet IS NOT NULL
GROUP BY 1,2 ORDER BY count(*) DESC LIMIT 40""",{},
    "LF7 je Anwalt — in welchem PLZ-Gebiet arbeitet welche Kanzlei. Coverage 459 Fälle mit PLZ.")

# 4) Kürzung je Anwalt (grain Anwalt, inkl. Kontextzeile 'kein Anwalt')
c4=card("Behauptete Kürzung je Anwalt","table","""
SELECT COALESCE(o.name,'(kein Anwalt erfasst — Altfall / ohne RA)') AS "Anwalt / Kanzlei",
       count(*) AS "Schreiben (n)", round(sum(k.kuerzungsbetrag),2) AS "Σ behauptete Kürzung €"
FROM core.fact_kuerzungsereignis k
LEFT JOIN core.fact_ausbuchung fa ON fa.aktenzeichen=k.aktenzeichen
LEFT JOIN core.dim_organisation o ON o.org_id=fa.anwalt_org_id
WHERE k.kuerzungsbetrag>0 GROUP BY 1 ORDER BY sum(k.kuerzungsbetrag) DESC""",{},
    "LF2 je Anwalt — Kürzungsbetrag aus den Schreiben. DÜNN: nur 7 von 39 Schreiben haben einen erfassten Anwalt, der Rest sind Altfälle/ohne RA (oberste Zeile).")

# 5) Kürzung je Anwalt × Versicherer
c5=card("Kürzung je Anwalt × Versicherer","table","""
SELECT o.name AS "Anwalt / Kanzlei", COALESCE(NULLIF(trim(k.versicherer),''),'(unbek.)') AS "Versicherer",
       count(*) AS "Schreiben (n)", round(sum(k.kuerzungsbetrag),2) AS "Σ Kürzung €"
FROM core.fact_kuerzungsereignis k
JOIN core.fact_ausbuchung fa ON fa.aktenzeichen=k.aktenzeichen
JOIN core.dim_organisation o ON o.org_id=fa.anwalt_org_id
WHERE k.kuerzungsbetrag>0 AND fa.anwalt_org_id IS NOT NULL
GROUP BY 1,2 ORDER BY sum(k.kuerzungsbetrag) DESC""",{},
    "LF2/3 — behauptete Kürzung je Kanzlei×Versicherer. Einzelfälle (n=1) — als Indikation.")

# 6) Durchsetzung belastbar je Anwalt × Versicherer
c6=card("Durchsetzungsquote je Anwalt × Versicherer (belastbar)","table","""
WITH k AS (SELECT aktenzeichen, max(versicherer) versicherer, sum(kuerzungsbetrag) kuerzung
           FROM core.fact_kuerzungsereignis WHERE kuerzungsbetrag>0 GROUP BY aktenzeichen),
a AS (SELECT aktenzeichen, sum(forderungsverlust_brutto) ausb FROM core.fact_forderungsverlust WHERE aktenzeichen IS NOT NULL GROUP BY aktenzeichen)
SELECT o.name AS "Anwalt / Kanzlei", COALESCE(NULLIF(trim(k.versicherer),''),'(unbek.)') AS "Versicherer",
       count(*) AS "Fälle (n)", round(sum(k.kuerzung),2) AS "Σ Kürzung €",
       round(sum(COALESCE(a.ausb,0)),2) AS "Σ Ausbuchung €",
       round(100*(1-sum(COALESCE(a.ausb,0))/NULLIF(sum(k.kuerzung),0)),1) AS "Durchgesetzt %"
FROM k JOIN core.fact_ausbuchung fa ON fa.aktenzeichen=k.aktenzeichen AND fa.won_time IS NOT NULL
JOIN core.dim_organisation o ON o.org_id=fa.anwalt_org_id
LEFT JOIN a ON a.aktenzeichen=k.aktenzeichen
WHERE COALESCE(a.ausb,0) <= k.kuerzung
GROUP BY 1,2 ORDER BY sum(k.kuerzung) DESC""",{},
    "LF3 — Durchsetzung (nur abgeschlossene, konsistente Fälle) je Kanzlei×Versicherer. Einzelfälle (n=1).")

# Dashboard
name="7 · Anwälte × Versicherer (Schaden · Geo · Kürzung · Durchsetzung)"
res=api("GET","/api/dashboard?f=all"); items=res if isinstance(res,list) else res.get("data",[])
dash=next((d["id"] for d in items if isinstance(d,dict) and d.get("name")==name and not d.get("archived")),None)
if not dash:
    dash=api("POST","/api/dashboard",{"name":name,"collection_id":COLL,
        "description":"Tiefe Kreuzauswertung Anwalt×Versicherer: Schadenhöhe, Einzugsgebiet (PLZ), Kürzung, Durchsetzung."})["id"]
TXT={"id":-99,"card_id":None,"col":0,"row":15,"size_x":24,"size_y":1,"parameter_mappings":[],
     "visualization_settings":{"text":"⚠️ **Kürzung & Durchsetzung je Anwalt sind dünn:** nur **7 von 39** Kürzungsschreiben haben einen erfassten Anwalt (Rest = Vor-Pipedrive-Altfälle / ohne RA). Jede Zeile ist praktisch ein **Einzelfall (n=1)** — als Indikation lesen, nicht als Statistik.","text.align_vertical":"middle"}}
layout=[(c1,0,0,24,8),(c2,0,8,12,7),(c3,12,8,12,7),(c4,0,16,24,6),(c5,0,22,12,7),(c6,12,22,12,7)]
dcs=[{"id":-(i+1),"card_id":cid,"col":col,"row":row,"size_x":sx,"size_y":sy,"parameter_mappings":[],"visualization_settings":{}}
     for i,(cid,col,row,sx,sy) in enumerate(layout)]
dcs.append(TXT)
api("PUT","/api/dashboard/%d"%dash,{"dashcards":dcs})
print("Dashboard",dash,"->",BASE+"/dashboard/%d"%dash)
