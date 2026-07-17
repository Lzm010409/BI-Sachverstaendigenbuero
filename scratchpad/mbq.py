#!/usr/bin/env python3
"""Metabase query helper. Runs native SQL against the warehouse (database id 2)
via POST /api/dataset using curl (proxy-friendly) + the read-only x-api-key.

Usage:
  python3 mbq.py "SELECT * FROM marts.v_geo_je_ort LIMIT 5"
  echo "SELECT ..." | python3 mbq.py -
  python3 mbq.py --json "SELECT ..."   # raw json
"""
import json, os, sys, subprocess

BASE = "https://metabase.gollenstede.app"
KEY = os.environ.get("METABASE_API_KEY") or os.environ.get("METABASE_ADMIN_KEY")
DB = 2

def run(sql, as_json=False):
    body = json.dumps({"database": DB, "type": "native", "native": {"query": sql}})
    out = subprocess.run(
        ["curl", "-sS", "-X", "POST", BASE + "/api/dataset",
         "-H", "Content-Type: application/json", "-H", "x-api-key: " + KEY,
         "-d", body], capture_output=True, text=True, timeout=180).stdout
    data = json.loads(out)
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2)); return
    d = data.get("data", {})
    if data.get("error") or data.get("status") == "failed":
        print("ERROR:", json.dumps(data, ensure_ascii=False)[:2000]); return
    cols = [c["name"] for c in d.get("cols", [])]
    rows = d.get("rows", [])
    print("\t".join(cols))
    for row in rows:
        print("\t".join("" if v is None else str(v) for v in row))
    print(f"-- {len(rows)} rows")

if __name__ == "__main__":
    args = sys.argv[1:]
    as_json = False
    if args and args[0] == "--json":
        as_json = True; args = args[1:]
    sql = sys.stdin.read() if (args and args[0] == "-") else " ".join(args)
    if not sql.strip():
        print("no sql"); sys.exit(1)
    run(sql, as_json)
