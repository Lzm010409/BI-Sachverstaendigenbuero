#!/usr/bin/env python3
"""Dashboard 6: Auftraggeber & Anwälte (LF4) + Versicherer×Anwalt.
Inline-SQL gegen core.* (metabase_ro liest core nach Deploy von sql/029/030).
Anwaltsnamen im Klartext (durchweg Rechtsanwälte, Inhaber bestätigt)."""
import json, os, subprocess, sys

BASE = "https://metabase.gollenstede.app"; KEY = os.environ["METABASE_API_KEY"]; DB = 2; COLL = 5

def api(method, path, body=None):
    args = ["curl", "-sS", "-X", method, BASE + path, "-H", "x-api-key: " + KEY]
    if body is not None:
        args += ["-H", "Content-Type: application/json", "--data-binary", "@-"]
    p = subprocess.run(args, input=(json.dumps(body) if body is not None else None),
                       capture_output=True, text=True, timeout=120)
    try: return json.loads(p.stdout)
    except Exception: return {"__raw": p.stdout[:300]}

def q(sql): return {"database": DB, "type": "native", "native": {"query": sql}}

def card(name, display, sql, viz, desc):
    r = api("POST", "/api/card", {"name": name, "display": display, "dataset_query": q(sql),
            "visualization_settings": viz, "collection_id": COLL, "description": desc})
    if "id" not in r: print("!! card err", name, json.dumps(r)[:300]); sys.exit(1)
    print(f"  card #{r['id']:>3} {display:<6} {name}")
    return r["id"]

FV = "WITH fv AS (SELECT aktenzeichen, sum(forderungsverlust_brutto) ausb FROM core.fact_forderungsverlust WHERE aktenzeichen IS NOT NULL GROUP BY aktenzeichen)"

# 1) LF4-Tabelle je Anwalt
c1 = card("Auftraggeber-Ranking (LF4): Umsatz, Fälle, Zahlungsausfall je Anwalt", "table",
    FV + """
SELECT COALESCE(o.name,'(unbekannt)') AS "Anwalt / Kanzlei",
       count(*) AS "Fälle",
       count(*) FILTER (WHERE fa.won_time IS NOT NULL) AS "davon won",
       round(sum(fa.deal_value_brutto),2) AS "Σ Umsatz brutto €",
       round(avg(fa.deal_value_brutto),2) AS "Ø je Fall €",
       round(COALESCE(sum(fv.ausb),0),2) AS "Σ Forderungsverlust €"
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_organisation o ON o.org_id=fa.anwalt_org_id
LEFT JOIN fv ON fv.aktenzeichen=fa.aktenzeichen
WHERE fa.anwalt_org_id IS NOT NULL
GROUP BY 1 ORDER BY sum(fa.deal_value_brutto) DESC""", {},
    "LF4 — welche Auftragsquelle bringt Umsatz UND zahlt zuverlässig? Forderungsverlust = "
    "tatsächlich abgeschriebene Beträge (LF5) je Kanzlei. Anwalt-Coverage 65% der Fälle.")

# 2) Umsatz je Anwalt — Balken (Top 15)
c2 = card("Umsatz je Anwalt/Kanzlei (Top 15)", "row",
    """SELECT COALESCE(o.name,'(unbekannt)') AS anwalt, round(sum(fa.deal_value_brutto),2) AS umsatz
FROM core.fact_ausbuchung fa LEFT JOIN core.dim_organisation o ON o.org_id=fa.anwalt_org_id
WHERE fa.anwalt_org_id IS NOT NULL GROUP BY 1 ORDER BY umsatz DESC LIMIT 15""",
    {"graph.dimensions": ["anwalt"], "graph.metrics": ["umsatz"],
     "graph.x_axis.title_text": "Anwalt/Kanzlei", "graph.y_axis.title_text": "Σ Umsatz brutto €"},
    "LF4 — Umsatzbeitrag je Auftraggeber (Top 15).")

# 3) Fälle je Anwalt — Balken (Top 15)
c3 = card("Fallzahl je Anwalt/Kanzlei (Top 15)", "row",
    """SELECT COALESCE(o.name,'(unbekannt)') AS anwalt, count(*) AS faelle
FROM core.fact_ausbuchung fa LEFT JOIN core.dim_organisation o ON o.org_id=fa.anwalt_org_id
WHERE fa.anwalt_org_id IS NOT NULL GROUP BY 1 ORDER BY faelle DESC LIMIT 15""",
    {"graph.dimensions": ["anwalt"], "graph.metrics": ["faelle"],
     "graph.x_axis.title_text": "Anwalt/Kanzlei", "graph.y_axis.title_text": "Anzahl Fälle"},
    "LF4 — Auftragsvolumen (Fallzahl) je Auftraggeber (Top 15).")

# 4) Versicherer × Anwalt — Kreuz-Tabelle (Top-Kombinationen)
c4 = card("Versicherer × Anwalt — Top-Kombinationen", "table",
    """SELECT COALESCE(NULLIF(trim(vo.name),''),'(kein/unbek. Versicherer)') AS "Versicherer",
       COALESCE(ao.name,'(unbekannt)') AS "Anwalt / Kanzlei",
       count(*) AS "Fälle",
       round(sum(fa.deal_value_brutto),2) AS "Σ Umsatz brutto €"
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_organisation vo ON vo.org_id=fa.org_id AND vo.typ='versicherer'
LEFT JOIN core.dim_organisation ao ON ao.org_id=fa.anwalt_org_id
WHERE fa.anwalt_org_id IS NOT NULL
GROUP BY 1,2 ORDER BY count(*) DESC LIMIT 40""", {},
    "Kreuzdimension: welche Kanzlei arbeitet gegen welchen Versicherer, wie oft. "
    "Versicherer = deal.org_id (Pipedrive, ~74% Coverage) → viele '(kein/unbek.)'. "
    "In Metabase per 'Pivot-Tabelle' interaktiv kreuzbar.")

# Dashboard anlegen/finden + Cards setzen
res = api("GET", "/api/dashboard?f=all")
items = res if isinstance(res, list) else res.get("data", [])
name = "6 · Auftraggeber & Anwälte (LF4)"
dash = next((d["id"] for d in items if isinstance(d, dict) and d.get("name") == name and not d.get("archived")), None)
if not dash:
    dash = api("POST", "/api/dashboard", {"name": name, "collection_id": COLL,
        "description": "Auftraggeber/Rechtsanwälte: Umsatz, Zahlungsverhalten, Versicherer×Anwalt (LF4)."})["id"]
H = 7
layout = [(c1, 0, 0, 24, 8), (c2, 0, 8, 12, H), (c3, 12, 8, 12, H), (c4, 0, 8 + H, 24, 9)]
dashcards = [{"id": -(i+1), "card_id": cid, "col": col, "row": row, "size_x": sx, "size_y": sy,
              "parameter_mappings": [], "visualization_settings": {}}
             for i, (cid, col, row, sx, sy) in enumerate(layout)]
api("PUT", "/api/dashboard/%d" % dash, {"dashcards": dashcards})
print("Dashboard", dash, "->", BASE + "/dashboard/%d" % dash)
