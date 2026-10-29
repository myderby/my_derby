#!/usr/bin/env python3
"""Create SQL to import exact, distinct 2025 KRA race programmes (no credentials)."""
from __future__ import annotations
import argparse
import csv
import datetime as dt
import pathlib
import re

FIELDS = ("rcDate", "meet", "rcNo", "rank", "rcDist", "stTime")
MEETS = {"서울", "부산경남", "제주"}


def sql_quote(value: object) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def parse_csv(path: pathlib.Path) -> list[dict[str, object]]:
    races: dict[tuple[str, str, int], dict[str, object]] = {}
    with path.open("r", encoding="utf-8-sig", newline="") as file:
        reader = csv.DictReader(file)
        if not set(FIELDS).issubset(reader.fieldnames or []):
            raise ValueError("Missing required columns: " + ", ".join(FIELDS))
        for line_no, row in enumerate(reader, 2):
            meet = (row["meet"] or "").strip()
            if meet not in MEETS:
                continue
            date = dt.datetime.strptime(row["rcDate"], "%Y%m%d").date()
            time = re.search(r"(\d{2}:\d{2})", row["stTime"] or "")
            if not time:
                raise ValueError(f"Missing stTime at row {line_no}")
            race_no = int(row["rcNo"])
            distance = int(row["rcDist"])
            if distance < 800 or distance > 3200:
                raise ValueError(f"Unsupported distance {distance} at row {line_no}")
            obj = dict(date=date.isoformat(), meet=meet, raceNo=race_no,
                       rank=row["rank"], dist=distance, stTime=time.group(1),
                       name=row.get("rcName") or "")
            key = (obj["date"], meet, race_no)
            if key in races and any(races[key][k] != obj[k] for k in ("rank", "dist", "stTime")):
                raise ValueError(f"Inconsistent duplicate race at row {line_no}: {key}")
            races[key] = obj
    return sorted(races.values(), key=lambda x: (x["date"], x["meet"], x["raceNo"]))


def export_sql(rows: list[dict[str, object]], path: pathlib.Path) -> None:
    with path.open("w", encoding="utf-8") as f:
        f.write("-- Import distinct (source_date, meet, rcNo) schedules; UTF-8.\n")
        for start in range(0, len(rows), 200):
            parts = []
            for r in rows[start:start + 200]:
                parts.append("(" + ",".join([
                    sql_quote(r["date"]), sql_quote(r["meet"]), str(r["raceNo"]),
                    sql_quote(r["rank"]), str(r["dist"]),
                    sql_quote(r["stTime"]), sql_quote(r["name"])
                ]) + ")")
            f.write(
                "insert into my_derby.race_program_source_2025("
                "source_date,source_meet,source_rc_no,source_rank,"
                "distance_m,original_st_time,original_rc_name) values\n"
                + ",\n".join(parts)
                + "\non conflict(source_date,source_meet,source_rc_no)"
                " do update set source_rank=excluded.source_rank,"
                " distance_m=excluded.distance_m,"
                " original_st_time=excluded.original_st_time,"
                " original_rc_name=excluded.original_rc_name;\n"
            )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("ranked_schedule_import.sql"))
    arguments = parser.parse_args()
    items = parse_csv(arguments.source)
    export_sql(items, arguments.output)
    print(f"Created {arguments.output} from {len(items)} distinct races")
