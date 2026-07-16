# n8n-Workflows (versioniert)

SDK-Quellcode der n8n-Workflows dieses Projekts (Referenz/Versionierung). Angelegt
werden sie über den n8n-MCP (`create_workflow_from_code`); Änderungen hier + neu
anlegen/aktualisieren.

## phase4-gutachten-fachwerte.workflow.ts
**n8n-ID:** `BHUg2f27aafCfI5Q` · **URL:** https://n8n-coolify.gollenstede.app/workflow/BHUg2f27aafCfI5Q

Liest je offenem, geschlossenem Fall (`raw.pipedrive_deals` status=won, ohne Zeile in
`raw.gutachten_fachwerte`) das Gutachten-PDF aus OneDrive (Microsoft Graph),
extrahiert den Text, parst die „Zusammenfassung des Gutachtens" (WBW/Restwert/
Wertminderung/Reparatur/Nutzungsausfall/Beurteilung — DSGVO: nur Zahlen) und
upsertet nach `raw.gutachten_fachwerte`. Der ETL/`migrate` baut daraus
`core.fact_gutachten` + Marts (`sql/016`).

**Vor Aktivierung zu verdrahten (in der n8n-UI):**
1. **Credential „Warehouse Postgres"** (Node „Offene Aktenzeichen" + „Upsert Fachwerte"):
   auf die Warehouse-DB. **Voraussetzung: n8n erreicht die Warehouse-Postgres** (ggf.
   n8n-Service ans `WAREHOUSE_NETWORK` hängen, wie der ETL-Container).
2. **Credential „Microsoft Graph OAuth2"** (Node „Suche Gutachten (Graph)"): OAuth2
   mit Graph-Scope `Files.Read.All`/`Sites.Read.All`. Der Download-Node braucht keine
   Auth (Graph liefert eine vorautorisierte `@microsoft.graph.downloadUrl`).
3. **OneDrive-Pfad prüfen:** Suche läuft über `/me/drive/root/search(q='<ordner>')`
   (ordner = Aktenzeichen mit `_`, z. B. `0625_1630TG`). Liegen die Gutachten in einer
   SharePoint-Site statt im persönlichen OneDrive, den Graph-Pfad auf
   `/sites/{siteId}/drive/...` bzw. die Site-Suche umstellen.
4. **Testlauf** manuell mit wenigen Fällen; Ergebnis über Metabase prüfen
   (`select count(*) from core.fact_gutachten`).

Parser-Referenz (identische Logik, getestet): `etl/gutachten/parse-fachwerte.ts`.
