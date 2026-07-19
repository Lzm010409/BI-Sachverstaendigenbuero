/**
 * pdf-text.ts — Textlayer eines PDFs (Buffer) extrahieren. Die autoiXpert-Gutachten
 * sind textbasiert (kein Scan) → kein OCR nötig; pdf-parse liefert den Textlayer,
 * der whitespace-tolerante parse-fachwerte.ts frisst ihn direkt.
 */
// Direkt das Lib-File importieren, NICHT den Index: pdf-parse/index.js führt beim
// Laden Debug-Code aus (liest eine Test-PDF → ENOENT unter ESM). Das Lib-File nicht.
import pdfParse from "pdf-parse/lib/pdf-parse.js";

export async function pdfToText(buf: Buffer): Promise<string> {
  const data = await pdfParse(buf);
  return data.text ?? "";
}
