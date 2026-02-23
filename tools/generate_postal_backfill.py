import csv
import re
from pathlib import Path


SRC = Path(r"C:\Users\chadi\OneDrive\Documents\AigleInfo\Project_Dispatch\Web_app\dispatch-calendar\TDL GOCO Assignments v2.csv")
OUT = Path(r"C:\Users\chadi\OneDrive\Documents\AigleInfo\Project_Dispatch\Web_app\dispatch-calendar\db\17_backfill_postal_from_csv.sql")


def normalize_postal(value: str) -> str:
    m = re.search(r"([A-Za-z]\d[A-Za-z])[ -]?(\d[A-Za-z]\d)", (value or "").upper())
    if not m:
        return ""
    return f"{m.group(1)} {m.group(2)}"


def sql_quote(value: str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


rows = []
seen = set()
with SRC.open("r", encoding="utf-8-sig", newline="") as f:
    reader = csv.DictReader(f)
    for row in reader:
        wo = (row.get("work_order") or "").strip()
        postal = normalize_postal(row.get("postal_code") or "")
        if not postal:
            blob = " ".join([
                row.get("address") or "",
                row.get("city") or "",
                row.get("postal_code") or "",
            ])
            postal = normalize_postal(blob)
        if not wo or not postal:
            continue
        key = (wo, postal)
        if key in seen:
            continue
        seen.add(key)
        rows.append(key)


lines = []
lines.append("-- Backfill jobs.postal_code from local CSV source (TDL GOCO Assignments v2.csv)")
lines.append("begin;")
lines.append("create temp table _postal_src(work_order text primary key, postal_code text not null);")
lines.append("insert into _postal_src(work_order, postal_code) values")
lines.append(",\n".join([f"  ({sql_quote(wo)}, {sql_quote(pc)})" for wo, pc in rows]) + ";")
lines.append("")
lines.append("update public.jobs j")
lines.append("set postal_code = s.postal_code")
lines.append("from _postal_src s")
lines.append("where trim(coalesce(j.wo,'')) = s.work_order")
lines.append("  and coalesce(trim(j.postal_code),'') <> s.postal_code;")
lines.append("")
lines.append("select count(*) as matched_rows")
lines.append("from public.jobs j")
lines.append("join _postal_src s on trim(coalesce(j.wo,'')) = s.work_order")
lines.append("where coalesce(trim(j.postal_code),'') = s.postal_code;")
lines.append("")
lines.append("commit;")

OUT.write_text("\n".join(lines), encoding="utf-8")
print(f"Generated: {OUT}")
print(f"Rows prepared: {len(rows)}")
