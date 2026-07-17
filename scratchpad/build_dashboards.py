#!/usr/bin/env python3
"""Legt in Metabase (v0.62, DB id 2) 5 Dashboards mit Cards an.
Idempotent: Sammlung/Dashboards werden per Name gefunden-oder-erstellt; ein
Dashboard wird bei Re-Run mit frischen Cards neu bestückt (alte Dashcards weg).
Nutzt curl (proxy-freundlich). Key: METABASE_API_KEY (User hat RW-Rechte)."""
import json, os, subprocess, sys

BASE = "https://metabase.gollenstede.app"
KEY = os.environ["METABASE_API_KEY"]
DB = 2
COLL_NAME = "BI — Kfz-Sachverständigenbüro"

def api(method, path, body=None):
    args = ["curl", "-sS", "-X", method, BASE + path,
            "-H", "x-api-key: " + KEY]
    if body is not None:
        args += ["-H", "Content-Type: application/json", "--data-binary", "@-"]
    p = subprocess.run(args, input=(json.dumps(body) if body is not None else None),
                       capture_output=True, text=True, timeout=180)
    out = p.stdout.strip()
    try:
        return json.loads(out)
    except Exception:
        return {"__raw": out, "__stderr": p.stderr}

def q(sql):
    return {"database": DB, "type": "native", "native": {"query": sql}}

# ---- Sammlung finden oder anlegen ------------------------------------------
def get_collection():
    for c in api("GET", "/api/collection"):
        if isinstance(c, dict) and c.get("name") == COLL_NAME:
            return c["id"]
    r = api("POST", "/api/collection", {"name": COLL_NAME,
            "description": "Entscheidungs-Dashboards (10 Leitfragen). Automatisch angelegt."})
    return r["id"]

# ---- Card anlegen (in Sammlung) --------------------------------------------
def make_card(coll_id, name, sql, display, viz, description=None):
    body = {"name": name, "display": display, "dataset_query": q(sql),
            "visualization_settings": viz, "collection_id": coll_id}
    if description:
        body["description"] = description
    r = api("POST", "/api/card", body)
    if "id" not in r:
        print("  !! Card-Fehler:", name, json.dumps(r)[:400]); sys.exit(1)
    print(f"  card #{r['id']:>3}  {display:<7} {name}")
    return r["id"]

# ---- Dashboard finden/anlegen ----------------------------------------------
def get_or_create_dashboard(coll_id, name, description):
    res = api("GET", "/api/dashboard?f=all")
    items = res if isinstance(res, list) else res.get("data", [])
    for d in items:
        if isinstance(d, dict) and d.get("name") == name and not d.get("archived"):
            return d["id"]
    r = api("POST", "/api/dashboard", {"name": name, "description": description,
            "collection_id": coll_id})
    return r["id"]

def set_dashcards(dash_id, layout):
    """layout: list of (card_id, col,row,size_x,size_y)."""
    dashcards = []
    for i, (cid, col, row, sx, sy) in enumerate(layout):
        dashcards.append({"id": -(i + 1), "card_id": cid, "col": col, "row": row,
                          "size_x": sx, "size_y": sy,
                          "parameter_mappings": [], "visualization_settings": {}})
    r = api("PUT", "/api/dashboard/%d" % dash_id, {"dashcards": dashcards})
    ok = "dashcards" in r or "id" in r
    print(f"  -> {len(dashcards)} dashcards gesetzt (ok={ok})")
    return r

# ============================================================================
def main():
    coll = get_collection()
    print("Sammlung id", coll)
    W = 24  # Metabase-Grid-Breite
    H = 7   # Standard-Kartenhöhe

    # ---------- Dashboard 1: Durchsetzung & Kürzungen (LF2/3) ---------------
    print("\n[1] Durchsetzung & Kürzungen (LF2/3)")
    c1 = make_card(coll, "Kürzung je Versicherer (echt, aus Kürzungsschreiben)",
        "SELECT versicherer, summe_kuerzung FROM marts.v_kuerzung_echt_je_versicherer "
        "WHERE versicherer <> '(unbekannt)' ORDER BY summe_kuerzung DESC",
        "row", {"graph.dimensions": ["versicherer"], "graph.metrics": ["summe_kuerzung"],
                "graph.x_axis.title_text": "Versicherer", "graph.y_axis.title_text": "Σ Kürzung (brutto, €)"},
        "LF2 — behauptete Kürzung je Versicherer (Versicherer-Behauptung aus den Schreiben).")
    c2 = make_card(coll, "Durchsetzungsquote je Versicherer (echt)",
        "SELECT versicherer, durchsetzungsquote, summe_kuerzung FROM marts.v_durchsetzung_echt "
        "WHERE versicherer <> '(unbekannt)' ORDER BY summe_kuerzung DESC",
        "row", {"graph.dimensions": ["versicherer"], "graph.metrics": ["durchsetzungsquote"],
                "graph.x_axis.title_text": "Versicherer", "graph.y_axis.title_text": "Durchsetzungsquote"},
        "LF3 — 1 − Σ Ausbuchung / Σ Kürzung. Höher = mehr durchgesetzt.")
    c3 = make_card(coll, "Durchsetzung je Fall (sevDesk-Methode)",
        "SELECT aktenzeichen, durchsetzungsquote, kuerzung_berechnet FROM marts.v_durchsetzung_sevdesk "
        "ORDER BY kuerzung_berechnet DESC",
        "row", {"graph.dimensions": ["aktenzeichen"], "graph.metrics": ["durchsetzungsquote"],
                "graph.x_axis.title_text": "Aktenzeichen", "graph.y_axis.title_text": "Durchsetzungsquote"},
        "LF3 — fakturiert − gezahlt_sv (Brief) je plausiblem Fall.")
    c4 = make_card(coll, "Kürzungs-Diagnose (sevDesk-Methode): Befund-Verteilung",
        "SELECT befund, count(*) AS anzahl FROM marts.v_kuerzung_sevdesk_diagnose "
        "GROUP BY befund ORDER BY anzahl DESC",
        "row", {"graph.dimensions": ["befund"], "graph.metrics": ["anzahl"],
                "graph.x_axis.title_text": "Befund", "graph.y_axis.title_text": "Anzahl Fälle"},
        "Datenqualität: welche Fälle die sevDesk-Methode trägt vs. verwirft.")
    d1 = get_or_create_dashboard(coll, "1 · Durchsetzung & Kürzungen (LF2/3)",
        "Behauptete Kürzung, tatsächliche Ausbuchung und Durchsetzungsquote je Versicherer/Fall.")
    set_dashcards(d1, [(c1, 0, 0, 12, H), (c2, 12, 0, 12, H),
                       (c3, 0, H, 12, H), (c4, 12, H, 12, H)])

    # ---------- Dashboard 2: Gutachten & Totalschaden (LF8/10) --------------
    print("\n[2] Gutachten & Totalschaden (LF8/10)")
    c1 = make_card(coll, "Totalschaden- & 130%-Quote je Monat",
        "SELECT monat, anzahl_gutachten, anzahl_totalschaden, totalschaden_quote "
        "FROM marts.v_totalschaden_quote WHERE monat >= DATE '2025-02-01' ORDER BY monat",
        "combo", {"graph.dimensions": ["monat"],
                  "graph.metrics": ["anzahl_gutachten", "anzahl_totalschaden", "totalschaden_quote"],
                  "series_settings": {"totalschaden_quote": {"axis": "right", "display": "line"},
                                      "anzahl_gutachten": {"display": "bar"},
                                      "anzahl_totalschaden": {"display": "bar"}},
                  "graph.x_axis.title_text": "Monat", "graph.y_axis.title_text": "Anzahl Gutachten"},
        "LF10 — Totalschaden-/130%-Quote im Zeitverlauf.")
    c2 = make_card(coll, "Honorar vs. Schadenhöhe (BVSK-Korridor)",
        "SELECT schadenhoehe_brutto, grundhonorar_netto FROM marts.v_honorar_vs_schaden "
        "WHERE schadenhoehe_brutto > 0 AND grundhonorar_netto > 0 AND schadenhoehe_brutto < 60000",
        "scatter", {"graph.dimensions": ["schadenhoehe_brutto"], "graph.metrics": ["grundhonorar_netto"],
                    "graph.x_axis.title_text": "Schadenhöhe brutto (€)",
                    "graph.y_axis.title_text": "Grundhonorar netto (€)"},
        "LF8 — Grundhonorar gegen Schadenhöhe (BVSK-Korridor). >60k€ ausgeblendet.")
    mix_sql = ("SELECT CASE WHEN beurteilung='Bewertung' THEN 'Bewertung' "
               "WHEN ueber_130_prozent THEN 'Totalschaden (>130%)' "
               "WHEN ist_totalschaden THEN 'Totalschaden' ELSE 'Reparaturschaden' END AS kategorie, "
               "count(*) AS anzahl, round(avg(nutzungsausfall_tagessatz),2) AS avg_nutzungsausfall, "
               "round(avg(reparaturdauer_tage),1) AS avg_reparaturdauer "
               "FROM core.fact_gutachten GROUP BY 1 ORDER BY anzahl DESC")
    c3 = make_card(coll, "Beurteilungs-Mix (Gutachten)", mix_sql,
        "pie", {"pie.dimension": "kategorie", "pie.metric": "anzahl"},
        "LF10 — Verteilung Reparatur- vs. Totalschaden vs. Bewertung.")
    c4 = make_card(coll, "Ø Nutzungsausfall-Tagessatz & Reparaturdauer je Kategorie", mix_sql,
        "bar", {"graph.dimensions": ["kategorie"],
                "graph.metrics": ["avg_nutzungsausfall", "avg_reparaturdauer"],
                "graph.x_axis.title_text": "Kategorie", "graph.y_axis.title_text": "Ø Wert"},
        "Ø Nutzungsausfall (€/Tag) und Ø Reparaturdauer (Tage) je Kategorie.")
    d2 = get_or_create_dashboard(coll, "2 · Gutachten & Totalschaden (LF8/10)",
        "Totalschaden-/130%-Quote, Honorar-vs-Schaden (BVSK) und Gutachten-Mix.")
    set_dashcards(d2, [(c1, 0, 0, 24, H), (c2, 0, H, 12, H),
                       (c3, 12, H, 6, H), (c4, 18, H, 6, H)])

    # ---------- Dashboard 3: Umsatz & Zahlungsausfälle ----------------------
    print("\n[3] Umsatz & Zahlungsausfälle")
    c1 = make_card(coll, "Umsatz je Monat (gestapelt nach Positionskategorie)",
        "SELECT monat, kategorie, summe_brutto FROM marts.v_rechnungsposition_monat "
        "WHERE monat >= DATE '2024-01-01' ORDER BY monat",
        "bar", {"graph.dimensions": ["monat", "kategorie"], "graph.metrics": ["summe_brutto"],
                "stackable.stack_type": "stacked",
                "graph.x_axis.title_text": "Monat", "graph.y_axis.title_text": "Σ brutto (€)"},
        "Fakturierter Umsatz je Monat, gestapelt nach Positionskategorie.")
    c2 = make_card(coll, "Umsatz je Positionskategorie (gesamt)",
        "SELECT kategorie, summe_brutto FROM marts.v_position_je_kategorie ORDER BY summe_brutto DESC",
        "row", {"graph.dimensions": ["kategorie"], "graph.metrics": ["summe_brutto"],
                "graph.x_axis.title_text": "Kategorie", "graph.y_axis.title_text": "Σ brutto (€)"},
        "Umsatzbeitrag je Positionskategorie über alle Rechnungen.")
    c3 = make_card(coll, "Forderungsverlust je Versicherer (LF5)",
        "SELECT versicherer, summe_ausbuchung, anzahl_faelle FROM marts.v_forderungsverlust_je_versicherer "
        "ORDER BY summe_ausbuchung DESC",
        "row", {"graph.dimensions": ["versicherer"], "graph.metrics": ["summe_ausbuchung"],
                "graph.x_axis.title_text": "Versicherer", "graph.y_axis.title_text": "Σ Ausbuchung (€)"},
        "LF5 — tatsächlich abgeschriebene Forderungen je Versicherer.")
    c4 = make_card(coll, "Forderungsverlust je Monat",
        "SELECT monat, summe_ausbuchung, anzahl_belege FROM marts.v_forderungsverlust_monat ORDER BY monat",
        "combo", {"graph.dimensions": ["monat"], "graph.metrics": ["summe_ausbuchung", "anzahl_belege"],
                  "series_settings": {"anzahl_belege": {"axis": "right", "display": "line"},
                                      "summe_ausbuchung": {"display": "bar"}},
                  "graph.x_axis.title_text": "Monat", "graph.y_axis.title_text": "Σ Ausbuchung (€)"},
        "LF5 — Forderungsverlust im Zeitverlauf.")
    d3 = get_or_create_dashboard(coll, "3 · Umsatz & Zahlungsausfälle (LF5)",
        "Umsatz nach Positionskategorie/Monat und tatsächliche Forderungsverluste.")
    set_dashcards(d3, [(c1, 0, 0, 24, H), (c2, 0, H, 12, H + 1),
                       (c3, 12, H, 12, H + 1), (c4, 0, 2 * H + 1, 24, H)])

    # ---------- Dashboard 4: Einzugsgebiet Geo (LF7) ------------------------
    print("\n[4] Einzugsgebiet Geo (LF7)")
    c1 = make_card(coll, "Umsatz & Fälle je PLZ-Gebiet",
        "SELECT plz_gebiet, summe_fakturiert_brutto, anzahl_faelle FROM marts.v_geo_je_plzgebiet "
        "WHERE plz_gebiet <> '(unbekannt)' ORDER BY summe_fakturiert_brutto DESC",
        "row", {"graph.dimensions": ["plz_gebiet"], "graph.metrics": ["summe_fakturiert_brutto"],
                "graph.x_axis.title_text": "PLZ-Gebiet (2-stellig)", "graph.y_axis.title_text": "Σ fakturiert (€)"},
        "LF7 — Umsatz je 2-stelligem PLZ-Gebiet. Ohne (unbekannt) ~48% Coverage.")
    c2 = make_card(coll, "Fälle je Ort (≥3 Fälle, DSGVO-aggregiert)",
        "SELECT ort, anzahl_faelle, summe_fakturiert_brutto FROM marts.v_geo_je_ort "
        "WHERE ort NOT IN ('(unbekannt)') AND anzahl_faelle >= 3 ORDER BY anzahl_faelle DESC",
        "row", {"graph.dimensions": ["ort"], "graph.metrics": ["anzahl_faelle"],
                "graph.x_axis.title_text": "Ort", "graph.y_axis.title_text": "Anzahl Fälle"},
        "LF7 — nur Orte mit ≥3 Fällen (Kleinstfälle wg. DSGVO ausgeblendet).")
    d4 = get_or_create_dashboard(coll, "4 · Einzugsgebiet (Geo, LF7)",
        "Umsatz und Fallzahl je PLZ-Gebiet und Ort (DSGVO-aggregiert).")
    set_dashcards(d4, [(c1, 0, 0, 12, H + 2), (c2, 12, 0, 12, H + 2)])

    # ---------- Dashboard 5: Auftragseingang & Saisonalität (LF9) -----------
    print("\n[5] Auftragseingang & Saisonalität (LF9)")
    c1 = make_card(coll, "Auftragseingang je Monat",
        "SELECT date_trunc('month', add_time)::date AS monat, count(*) AS anzahl_auftraege "
        "FROM core.fact_ausbuchung WHERE add_time >= DATE '2024-11-01' GROUP BY 1 ORDER BY 1",
        "bar", {"graph.dimensions": ["monat"], "graph.metrics": ["anzahl_auftraege"],
                "graph.x_axis.title_text": "Monat", "graph.y_axis.title_text": "Aufträge"},
        "LF9 — Auftragseingang im Zeitverlauf (Go-Live-Import 2024-10 ausgeblendet).")
    c2 = make_card(coll, "Saisonalität: Ø Auftragseingang je Kalendermonat",
        "SELECT to_char(add_time, 'MM Mon') AS kalendermonat, "
        "round(count(*)::numeric / count(DISTINCT date_trunc('year', add_time)), 1) AS schnitt_auftraege "
        "FROM core.fact_ausbuchung WHERE add_time >= DATE '2024-11-01' GROUP BY 1 ORDER BY 1",
        "bar", {"graph.dimensions": ["kalendermonat"], "graph.metrics": ["schnitt_auftraege"],
                "graph.x_axis.title_text": "Kalendermonat", "graph.y_axis.title_text": "Ø Aufträge / Jahr"},
        "LF9 — Saisonmuster: durchschnittlicher Auftragseingang je Kalendermonat.")
    d5 = get_or_create_dashboard(coll, "5 · Auftragseingang & Saisonalität (LF9)",
        "Auftragseingang je Monat und Saisonmuster je Kalendermonat.")
    set_dashcards(d5, [(c1, 0, 0, 24, H), (c2, 0, H, 24, H)])

    print("\nFertig. Sammlung:", BASE + "/collection/%d" % coll)

if __name__ == "__main__":
    main()
