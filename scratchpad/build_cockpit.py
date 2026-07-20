#!/usr/bin/env python3
"""Stufe C — Management-Cockpit: eine Seite mit den wichtigsten KPIs über alle 10
Leitfragen (große Zahlen + Ampel-Gauges). Inline-SQL auf bestehende Views → sofort live.
Dashboard als ERSTES in der Sammlung (Startseite)."""
import json, os, subprocess
BASE="https://metabase.gollenstede.app"; KEY=os.environ["METABASE_API_KEY"]; DB=2; COLL=5

def api(m,p,b=None):
    a=["curl","-sS","-X",m,BASE+p,"-H","x-api-key: "+KEY]
    if b is not None: a+=["-H","Content-Type: application/json","--data-binary","@-"]
    r=subprocess.run(a,input=(json.dumps(b) if b is not None else None),capture_output=True,text=True,timeout=90)
    try: return json.loads(r.stdout)
    except: return {"__raw":r.stdout[:300]}
def q(s): return {"database":DB,"type":"native","native":{"query":s}}
def card(name,display,sql,viz,desc):
    r=api("POST","/api/card",{"name":name,"display":display,"dataset_query":q(sql),
          "visualization_settings":viz,"collection_id":COLL,"description":desc})
    print("card",r.get("id"),name[:40]); return r["id"]

AMPEL=lambda lo,hi:[{"min":0,"max":lo,"color":"#ED6E6E"},{"min":lo,"max":hi,"color":"#F9CF48"},{"min":hi,"max":100,"color":"#84C868"}]
def scalar(name,sql,desc,suffix=""):
    viz={"column_settings":{}} if not suffix else {}
    return card(name,"scalar",sql,{},desc)
def gauge(name,sql,lo,hi,desc):
    return card(name,"gauge",sql,{"gauge.segments":AMPEL(lo,hi)},desc)

cards=[]
# Zeile 1 — Geschäft aktueller Monat + Durchsetzung
cards.append(scalar("Umsatz laufender Monat (€ brutto)",
  "SELECT round(sum(deal_value_brutto)) FROM core.fact_ausbuchung WHERE won_time >= date_trunc('month', now())",
  "Fakturierter Umsatz (brutto) der im laufenden Monat bezahlten/geschlossenen Fälle."))
cards.append(scalar("Fälle bezahlt (laufender Monat)",
  "SELECT count(*) FROM core.fact_ausbuchung WHERE won_time >= date_trunc('month', now())",
  "Anzahl im laufenden Monat auf 'bezahlt' geschlossener Fälle (won_time)."))
cards.append(gauge("Durchsetzungsquote % (LF2/3)",
  "SELECT round(100*(1-sum(ausgebucht)/NULLIF(sum(kuerzung),0)),1) FROM marts.v_durchsetzung_zahlung",70,85,
  "Zahlungsbasiert: 1 − Σ Ausbuchung / Σ Kürzung. Wie viel der Versicherer-Kürzungen "
  "wir tatsächlich durchsetzen. Ampel: <70 kritisch, 70–85 ok, >85 gut."))
cards.append(scalar("Forderungsverlust gesamt (€)",
  "SELECT round(sum(summe_ausbuchung)) FROM marts.v_forderungsverlust_je_versicherer",
  "LF5 — Summe der tatsächlich ausgebuchten (verlorenen) Beträge über alle Versicherer."))

# Zeile 2 — Rentabilität + Durchlauf
cards.append(gauge("Deckungsbeitrag-Marge Haftpflicht % (LF1)",
  "SELECT marge_pct FROM marts.v_deckungsbeitrag_je_auftragsart WHERE auftragsart='Haftpflicht'",40,60,
  "Vollkosten-Marge der Haftpflichtgutachten (Modellrechnung, Zeit geschätzt). "
  "Ampel: <40 dünn, 40–60 ok, >60 gut."))
cards.append(gauge("Honorar-Konformität % im BVSK-Korridor (LF8)",
  "SELECT round(100.0*count(*) FILTER (WHERE befund='konform')/count(*),1) FROM marts.v_honorar_konformitaet",70,85,
  "Anteil der Fälle, deren Honorar im BVSK-Tabellenkorridor liegt (weder deutlich über "
  "noch unter). Ampel: <70 prüfen, >85 gut."))
cards.append(scalar("Median Durchlaufzeit (Tage, LF6)",
  "SELECT median_tage FROM marts.v_durchlaufzeit",
  "LF6 — Median-Tage vom Anlegen bis zur Bezahlung (won). Median statt Ø, weil Klage-"
  "Langläufer den Schnitt verzerren."))
cards.append(scalar("Offen im 'Versendet'-Stau >30 Tage (LF6)",
  "SELECT aelter_30_tage FROM marts.v_stage_offen WHERE stage='Versendet'",
  "LF6 — offene Fälle, die seit >30 Tagen im Stage 'Versendet' liegen (Rechnung raus, "
  "Zahlung offen). Der operative Haupt-Engpass."))

# Zeile 3 — Qualität/Struktur
cards.append(scalar("Totalschaden-Quote % (LF10)",
  "SELECT round(100.0*count(*) FILTER (WHERE ist_totalschaden)/NULLIF(count(*),0),1) FROM core.fact_gutachten",
  "LF10 — Anteil Totalschäden an allen Gutachten mit Fachwerten (Risiko-/Struktur-"
  "Indikator, korreliert mit Kürzungsdruck)."))
cards.append(scalar("Umsatz je gefahrenem km (€, LF7)",
  "SELECT round(sum(summe_umsatz_brutto)/NULLIF(sum(summe_km),0),2) FROM marts.v_umsatz_je_km WHERE plz_gebiet<>'(unbekannt)'",
  "LF7 — Umsatz (brutto) je gefahrenem Kilometer über alle Fälle mit km-Angabe. "
  "Rentabilität des Einzugsgebiets."))

d=api("POST","/api/dashboard",{"name":"0 · Management-Cockpit (Überblick)","collection_id":COLL,
  "description":"Die wichtigsten Kennzahlen über alle 10 Leitfragen auf einen Blick. "
                "Ampel-Gauges für Quoten, große Zahlen für Volumen. Startseite."})
did=d["id"]; print("dashboard",did,d.get("name"))
dcs=[]
for i,cid in enumerate(cards):
    col=(i%4)*6; row=(i//4)*4
    dcs.append({"id":-(i+1),"card_id":cid,"col":col,"row":row,"size_x":6,"size_y":4,
                "parameter_mappings":[],"visualization_settings":{}})
api("PUT","/api/dashboard/%d"%did,{"dashcards":dcs})
print("cockpit fertig, dashboard",did,"mit",len(cards),"KPIs")
