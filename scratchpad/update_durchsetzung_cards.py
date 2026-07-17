#!/usr/bin/env python3
"""Aktualisiert die Durchsetzungs-/Kürzungs-Cards (Dashboard 1) auf die
belastbare, ehrliche Logik: Quote nur für abgeschlossene (won) Fälle; fehlende
Ausbuchung = unbekannt (Fall zählt nicht als 100%). Inline-SQL gegen core.*, damit
sofort korrekt (unabhängig vom Deploy von sql/028). Tabellen zeigen n."""
import json, os, subprocess

BASE = "https://metabase.gollenstede.app"; KEY = os.environ["METABASE_API_KEY"]; DB = 2

def api(method, path, body):
    p = subprocess.run(["curl", "-sS", "-X", method, BASE + path, "-H", "x-api-key: " + KEY,
                        "-H", "Content-Type: application/json", "--data-binary", "@-"],
                       input=json.dumps(body), capture_output=True, text=True, timeout=120)
    return json.loads(p.stdout)

def q(sql): return {"database": DB, "type": "native", "native": {"query": sql}}

def update(cid, name, display, sql, viz, desc):
    r = api("PUT", "/api/card/%d" % cid,
            {"name": name, "display": display, "dataset_query": q(sql),
             "visualization_settings": viz, "description": desc})
    print(cid, "->", r.get("display"), r.get("name") if "name" in r else json.dumps(r)[:200])

# --- Card 42: Durchsetzung je Versicherer (echt) — Tabelle, nur won ----------
sql42 = """WITH k AS (
  SELECT aktenzeichen, max(versicherer) versicherer, sum(kuerzungsbetrag) kuerzung
  FROM core.fact_kuerzungsereignis WHERE kuerzungsbetrag>0 GROUP BY aktenzeichen),
a AS (SELECT aktenzeichen, sum(forderungsverlust_brutto) ausb
      FROM core.fact_forderungsverlust WHERE aktenzeichen IS NOT NULL GROUP BY aktenzeichen),
b AS (SELECT COALESCE(NULLIF(trim(k.versicherer),''),'(unbekannt)') versicherer, k.kuerzung, COALESCE(a.ausb,0) ausb
      FROM k JOIN core.fact_ausbuchung fa ON fa.aktenzeichen=k.aktenzeichen AND fa.won_time IS NOT NULL
      LEFT JOIN a ON a.aktenzeichen=k.aktenzeichen)
SELECT versicherer AS "Versicherer",
       count(*) AS "Fälle (n)",
       round(sum(kuerzung),2) AS "Σ Kürzung €",
       round(sum(ausb),2) AS "Σ Ausbuchung €",
       round(100*(1-sum(ausb)/NULLIF(sum(kuerzung),0)),1) AS "Durchgesetzt %"
FROM b GROUP BY versicherer ORDER BY sum(kuerzung) DESC"""
update(42, "Durchsetzungsquote je Versicherer (nur abgeschlossene Fälle)", "table", sql42, {},
    "LF3 — Quote NUR für abgeschlossene (won) Fälle mit bekannter Ausbuchung. "
    "Altfälle ohne sevDesk-Beleg fließen NICHT als 100% ein. n klein (meist 1–2) → "
    "je Versicherer eher Indikation als Statistik. Stand: 12 belastbare Fälle.")

# --- Card 43: Durchsetzung je Fall (sevDesk) — Tabelle, won & konsistent -----
sql43 = """WITH brief AS (
  SELECT aktenzeichen, max(versicherer) versicherer, max(sv_kosten_gezahlt) gezahlt_sv
  FROM core.fact_kuerzungsereignis WHERE sv_kosten_gezahlt IS NOT NULL GROUP BY aktenzeichen),
fakt AS (SELECT aktenzeichen, max(deal_value_brutto) fakturiert, bool_or(won_time IS NOT NULL) won
         FROM core.fact_ausbuchung GROUP BY aktenzeichen),
fv AS (SELECT aktenzeichen, sum(forderungsverlust_brutto) ausb
       FROM core.fact_forderungsverlust WHERE aktenzeichen IS NOT NULL GROUP BY aktenzeichen)
SELECT b.aktenzeichen AS "Aktenzeichen", b.versicherer AS "Versicherer",
       f.fakturiert AS "Fakturiert €", b.gezahlt_sv AS "Gezahlt SV €",
       round((f.fakturiert-b.gezahlt_sv)::numeric,2) AS "Kürzung €",
       COALESCE(fv.ausb,0) AS "Ausbuchung €",
       round(100*(1-COALESCE(fv.ausb,0)/NULLIF((f.fakturiert-b.gezahlt_sv),0)),1) AS "Durchgesetzt %"
FROM brief b JOIN fakt f USING(aktenzeichen) LEFT JOIN fv USING(aktenzeichen)
WHERE f.won AND f.fakturiert IS NOT NULL AND b.gezahlt_sv>0 AND b.gezahlt_sv<=f.fakturiert
  AND (f.fakturiert-b.gezahlt_sv)>1 AND COALESCE(fv.ausb,0)<=(f.fakturiert-b.gezahlt_sv)
ORDER BY (f.fakturiert-b.gezahlt_sv) DESC"""
update(43, "Durchsetzung je Fall (sevDesk-Methode, abgeschlossen & konsistent)", "table", sql43, {},
    "LF3 — fakturiert − gezahlt_sv (Brief) vs. tatsächliche Ausbuchung, je Fall. "
    "Nur won-Fälle; gezahlt_sv=0, Bagatelle (≤1€) und Quell-Inkonsistenzen "
    "(Ausbuchung>Kürzung) ausgefiltert. HINWEIS: 0525/1568TG (DEVK, 5.407€) am "
    "Originalschreiben prüfen — sehr hoher Einzelwert.")

# --- Card 44: Diagnose-Verteilung (erweitert) -------------------------------
sql44 = """WITH brief AS (
  SELECT aktenzeichen, max(sv_kosten_gezahlt) gezahlt_sv
  FROM core.fact_kuerzungsereignis WHERE sv_kosten_gezahlt IS NOT NULL GROUP BY aktenzeichen),
fakt AS (SELECT aktenzeichen, max(deal_value_brutto) fakturiert, bool_or(won_time IS NOT NULL) won
         FROM core.fact_ausbuchung GROUP BY aktenzeichen),
fv AS (SELECT aktenzeichen, sum(forderungsverlust_brutto) ausb
       FROM core.fact_forderungsverlust WHERE aktenzeichen IS NOT NULL GROUP BY aktenzeichen),
j AS (SELECT b.aktenzeichen, f.fakturiert, b.gezahlt_sv, COALESCE(f.won,false) won, COALESCE(fv.ausb,0) ausb
      FROM brief b LEFT JOIN fakt f USING(aktenzeichen) LEFT JOIN fv USING(aktenzeichen))
SELECT CASE
    WHEN fakturiert IS NULL THEN 'kein sevDesk-Fall (Altfall)'
    WHEN NOT won THEN 'noch offen (won fehlt)'
    WHEN gezahlt_sv>fakturiert THEN 'gezahlt>fakturiert (Fehl-Lesung)'
    WHEN gezahlt_sv=0 THEN 'gezahlt_sv=0 (Lese-Verdacht)'
    WHEN ausb>(fakturiert-gezahlt_sv) THEN 'inkonsistent: Ausbuchung>Kürzung'
    WHEN (fakturiert-gezahlt_sv)<=1 THEN 'voll gezahlt, keine Kürzung'
    ELSE 'verwertbar' END AS "Befund",
  count(*) AS "Anzahl Schreiben"
FROM j GROUP BY 1 ORDER BY 2 DESC"""
update(44, "Kürzungs-Diagnose (sevDesk-Methode): Verwertbarkeit der Schreiben", "row", sql44,
    {"graph.dimensions": ["Befund"], "graph.metrics": ["Anzahl Schreiben"],
     "graph.x_axis.title_text": "Befund", "graph.y_axis.title_text": "Anzahl Schreiben"},
    "Datenqualität: warum ein Schreiben (nicht) in die Quote eingeht. Nur "
    "'verwertbar' trägt die sevDesk-Durchsetzung.")

# --- Card 41: Beschreibung präzisieren (bleibt row/amounts, alle Fälle) ------
r = api("PUT", "/api/card/41", {"description":
    "LF2 — behauptete Kürzung je Versicherer (Betrag aus den Schreiben, ALLE Fälle "
    "inkl. Altfälle). Reiner Betrag, keine Quote. n je Versicherer meist 1 → als "
    "Indikation lesen. Für die Durchsetzung siehe rechte Cards (nur abgeschlossene Fälle)."})
print(41, "desc updated ->", r.get("name", json.dumps(r)[:120]))
