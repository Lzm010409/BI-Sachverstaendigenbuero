/**
 * fields.generated.ts — AUTOMATISCH GENERIERT von scripts/generate-fields.ts.
 * NICHT von Hand editieren. Quelle: docs/field-mapping.json.
 * Quelle-Stand: provisional-live-recon (2026-07-15).
 *
 * Solange source='provisional-live-recon' ist, sind Labels teils abgeleitet.
 * Nach `npm run fetch:fields` (Fields API v2) hier neu generieren.
 */


export const DEAL_FIELDS = {
  AUSGEBUCHT_BETRAG: "c4ae5d687eacc0bbe5c05a1d70ec447644d4eb3f",  // status=confirmed, dwh=include
  AUSGEBUCHT_GRUND: "a037653e87dd01a3ab9946c9741ff2db41de64f3",  // status=confirmed, dwh=include
  ENTHALTENE_MWST: "8e0a4e9266683b1a80cb216ab073e7c106fe85de",  // status=confirmed, dwh=include
  NETTOBETRAG: "7f32b816f86f61caf9012530d7b5d80efcb2476b",  // status=inferred, dwh=include
  REPARATURKOSTEN_BRUTTO: "adb0956f0161f534c04d43a1627acb23e692fea6",  // status=confirmed, dwh=include
  REPARATURKOSTEN_NETTO: "4ceb36746f5a9faa66cce4e2aa68f9191d43d7dc",  // status=confirmed, dwh=include
  HERSTELLER: "fb715086e3b3e7298a7926ca17b60ebeeae201b0",  // status=confirmed, dwh=include
  MODELL: "92bae1c60a08746cfa85a4d878703cf4a80e23f4",  // status=confirmed, dwh=include
  KENNZEICHEN: "00e9babb88454e04c01ae593a6402e8f9c401fb8",  // status=confirmed, dwh=exclude
  ERSTZULASSUNG: "2af7a9a816729e71b73e9bb11e293ef9c536fde1",  // status=confirmed, dwh=include
  SCHADENDATUM: "cff1b2f6dead55e1383e133c2a41ea11de8a8eb5",  // status=inferred, dwh=include
  DATUM_UNBEKANNT: "62a4930ba7b628e97fa23303a978588f8b68c146",  // status=needs_token, dwh=include
  FAHRZEUGALTER_KLASSE: "07e27cb2833479a4b38d15f28c318ae09df6bd19",  // status=confirmed, dwh=include
  SCHADENBEREICH: "e9201fb8139b256e85c3e5852c82b22ef7702443",  // status=confirmed, dwh=include
  UNFALLHERGANG: "5831d9e441cf674a193d8b7a2eb588300e00abc8",  // status=confirmed, dwh=exclude
  VORSCHADEN_JA_NEIN: "efd97e609ca237856d2a089a157a2a7023961df7",  // status=inferred, dwh=include
  VORSCHADEN_BESCHREIBUNG: "2b30a5b6f68afe5728c2aa9eb4b50075db57381a",  // status=inferred, dwh=exclude
  ALTSCHADEN_JA_NEIN: "3bc5c0f3ce4f5df55589d9dd88674dfb90d6110d",  // status=inferred, dwh=include
  ALTSCHADEN_BESCHREIBUNG: "537563a6b98dc7504f1b8142175a19232b3f3dd6",  // status=inferred, dwh=exclude
  NUTZUNGSAUSFALL_TAGESSATZ: "215832fc2c61f065e6ad134c2a46485911fdcf28",  // status=inferred, dwh=include
  NUTZUNGSAUSFALL_TAGE: "4476af4192da200827de0ce96e696a298372e729",  // status=inferred, dwh=include
  AUTOIXPERT_DEEPLINK: "102c6f8c0eb82cace7aa8ed3e77c06dcd3485a2a",  // status=confirmed, dwh=include
  AUTOIXPERT_GUTACHTEN_ID: "f6970a4fb3ed5c0520ba2ff1c84ec3becb422659",  // status=confirmed, dwh=include
  SEVDESK_RECHNUNGS_ID: "d8863fcbcb97aeb225a9418261b5508c0410783f",  // status=confirmed, dwh=include
  SEVDESK_DEEPLINK: "ee8bc622d857b546eca74c56a303f1373b05047c",  // status=confirmed, dwh=include
  MARKETING_EINWILLIGUNG: "64fea94aefeb55264354c0afa5677f89859100af",  // status=confirmed, dwh=exclude
  UNBEKANNT_621AFA76: "621afa76ad0e9c446f624588a0e964a6c31c8f93",  // status=needs_token, dwh=exclude
  UNBEKANNT_B189ECBD: "b189ecbd4510e9555bf8fbf5e8c2fa33159532ce",  // status=needs_token, dwh=exclude
} as const;

export const DEAL_OPTIONS = {
  AUSGEBUCHT_GRUND: { 70: "Nebenkosten" } as Record<number, string>,
  FAHRZEUGALTER_KLASSE: { 49: "Mittelalt", 51: "> 10 Jahre" } as Record<number, string>,
  SCHADENBEREICH: { 37: "Vorne", 39: "Vorne rechts", 40: "Mitte rechts", 43: "Hinten rechts", 44: "Hinten", 45: "Hinten links" } as Record<number, string>,
  VORSCHADEN_JA_NEIN: { 53: "Ja" } as Record<number, string>,
  ALTSCHADEN_JA_NEIN: { 55: "Ja", 56: "Nein" } as Record<number, string>,
  MARKETING_EINWILLIGUNG: { 57: "Infodienst", 58: "Newsletter" } as Record<number, string>,
} as const;

export const PERSON_FIELDS = {
} as const;

export const ORGANIZATION_FIELDS = {
  E_MAIL: "5076c4b60d419e0d1d19bb82423aff38fde5eaec",  // status=confirmed, dwh=include
  UNBEKANNT_F8457FC2: "f8457fc274acc8b82ae223f2c44d0dbdcf7ea755",  // status=needs_token, dwh=exclude
  UNBEKANNT_76710522: "76710522ad255259f10e92543a11efd390b2a115",  // status=needs_token, dwh=exclude
  UNBEKANNT_4A19D027: "4a19d027812882f1ebf2c05d2c0244905844c056",  // status=needs_token, dwh=exclude
  UNBEKANNT_8416EBAD: "8416ebad8a9070d24302005ac65acc297d2596c1",  // status=needs_token, dwh=exclude
  UNBEKANNT_5DEE7A36: "5dee7a360bb641334ce5d73b99d7e9690f5405de",  // status=needs_token, dwh=exclude
  UNBEKANNT_B70CC996: "b70cc996dae0ae86b46593dd2723b30bb0a9304f",  // status=needs_token, dwh=exclude
} as const;

/** DSGVO/Irrelevanz: diese Keys dürfen NICHT nach core/marts. */
export const DWH_EXCLUDED_KEYS: ReadonlySet<string> = new Set([
  "00e9babb88454e04c01ae593a6402e8f9c401fb8",
  "5831d9e441cf674a193d8b7a2eb588300e00abc8",
  "2b30a5b6f68afe5728c2aa9eb4b50075db57381a",
  "537563a6b98dc7504f1b8142175a19232b3f3dd6",
  "64fea94aefeb55264354c0afa5677f89859100af",
  "621afa76ad0e9c446f624588a0e964a6c31c8f93",
  "b189ecbd4510e9555bf8fbf5e8c2fa33159532ce",
  "f8457fc274acc8b82ae223f2c44d0dbdcf7ea755",
  "76710522ad255259f10e92543a11efd390b2a115",
  "4a19d027812882f1ebf2c05d2c0244905844c056",
  "8416ebad8a9070d24302005ac65acc297d2596c1",
  "5dee7a360bb641334ce5d73b99d7e9690f5405de",
  "b70cc996dae0ae86b46593dd2723b30bb0a9304f"
]);
