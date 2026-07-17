# Feldmapping (PROVISORISCH)

> **Provisorisch** aus Live-Stichproben abgeleitet, **nicht** aus dem
> Feldmetadaten-Endpunkt. Wird von `scripts/fetch-field-mapping.ts` (Pipedrive
> Fields API v2) überschrieben, sobald der read-only Token vorliegt.
> Narrative, offene Fragen und MENSCH-Entscheidungen: siehe
> `field-mapping-findings.md`. Maschinenform: `field-mapping.json`.
>
> Legende status: `confirmed` aus Werten belegt · `inferred` plausibel,
> unbestätigt · `needs_token` Bedeutung offen. dwh: `include` / `exclude`
> (exclude = DSGVO oder irrelevant).

## deal

| Key | Label (provisorisch) | Typ | status | dwh | Notiz |
|---|---|---|---|---|---|
| `c4ae5d68…` | Ausgebucht Betrag | monetary | confirmed | include | brutto; NULL≠0 |
| `a037653e…` | Ausgebucht Grund | enum | confirmed | include | Opt 70=Nebenkosten; Rest offen |
| `8e0a4e92…` | enthaltene MwSt | monetary | confirmed | include | = Netto·0,19 |
| `7f32b816…` | Nettobetrag | monetary | inferred | include | NEU; = value/1,19 |
| `adb0956f…` | Reparaturkosten brutto | monetary | confirmed | include | |
| `4ceb3674…` | Reparaturkosten netto | monetary | confirmed | include | |
| `fb715086…` | Hersteller | varchar | confirmed | include | dirty Freitext |
| `92bae1c6…` | Modell | varchar | confirmed | include | Freitext |
| `00e9babb…` | Kennzeichen | varchar | confirmed | **exclude** | DSGVO |
| `2af7a9a8…` | Erstzulassung | date | confirmed | include | |
| `cff1b2f6…` | Erwerbsdatum? | date | inferred | include | ❓ revidiert von Schadendatum (immer < add_time) |
| `62a4930b…` | Datum unbekannt | date | needs_token | include | NEU ❓ |
| `07e27cb2…` | Fahrzeugalter-Klasse | enum | confirmed | include | 49=Mittelalt, 51=>10 J. |
| `e9201fb8…` | Schadenbereich | set | confirmed | include | Mehrfachauswahl |
| `5831d9e4…` | Unfallhergang | text | confirmed | **exclude** | DSGVO Freitext |
| `efd97e60…` | Vorschaden (Ja/Nein)? | enum | inferred | include | ❓ vs Altschaden |
| `2b30a5b6…` | Vorschaden-Beschreibung? | text | inferred | **exclude** | DSGVO |
| `3bc5c0f3…` | Altschaden (Ja/Nein)? | enum | inferred | include | ❓ vs Vorschaden |
| `537563a6…` | Altschaden-Beschreibung? | text | inferred | **exclude** | DSGVO |
| `215832fc…` | **Rechtsanwalt/Kanzlei** | org-FK (numerisch) | confirmed | include | Inhaber bestätigt; Wert = `org_id` der Kanzlei → `dim_organisation`. NICHT Nutzungsausfall (Fehl-Inferenz). Join-Key LF4/Versicherer×Anwalt |
| `4476af41…` | unbekannt (kaum genutzt) | double | needs_token | exclude | ❓ 0/100 befüllt |
| `102c6f8c…` | autoiXpert Deeplink | varchar | confirmed | include | NEU |
| `f6970a4f…` | autoiXpert Gutachten-ID | varchar | confirmed | include | NEU; Join-Key Phase 4 |
| `d8863fcb…` | sevDesk Rechnungs-ID | varchar | confirmed | include | Join-Key Phase 3 |
| `ee8bc622…` | sevDesk Deeplink | varchar | confirmed | include | |
| `64fea94a…` | Marketing-Einwilligung | set | confirmed | **exclude** | irrelevant |
| `621afa76…` | unbekannt | ? | needs_token | exclude | immer null |
| `b189ecbd…` | unbekannt | ? | needs_token | exclude | immer null |

## organization

| Key | Label (provisorisch) | Typ | status | dwh | Notiz |
|---|---|---|---|---|---|
| `5076c4b6…` | E-Mail | varchar | confirmed | include | juristische Person |
| `f8457fc2…` … `b70cc996…` | unbekannt (6 Felder) | ? | needs_token | exclude | in Stichprobe null |

## person

Nicht abgetastet (enthalten überwiegend Personenbezug → Ziel: pseudonyme ID,
Klartextfelder `exclude`). Wird beim Token-Lauf ergänzt.
