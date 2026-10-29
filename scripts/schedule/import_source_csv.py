#!/usr/bin/env python3
"""Create SQL to import exact, distinct 2025 KRA race programmes (no credentials)."""
from __future__ import annotations
import argparse
import csv
import datetime as dt
import pathlib
import re

FIELDS = ("rcDate", "meet", "rcNo", "rank", "rcDist", "stTime", "dusu")
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
            dusu = int(row["dusu"])
            if not 2 <= dusu <= 16:
                raise ValueError(f"Unsupported dusu {dusu} at row {line_no}")
            if distance < 800 or distance > 3200:
                raise ValueError(f"Unsupported distance {distance} at row {line_no}")
            obj = dict(date=date.isoformat(), meet=meet, raceNo=race_no,
                       rank=row["rank"], dist=distance, dusu=dusu, stTime=time.group(1),
                       name=row.get("rcName") or "")
            key = (obj["date"], meet, race_no)
            if key in races and any(races[key][k] != obj[k] for k in ("rank", "dist", "stTime", "dusu")):
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
                    sql_quote(r["rank"]), str(r["dist"]), str(r["dusu"]),
                    sql_quote(r["stTime"]), sql_quote(r["name"])
                ]) + ")")
            f.write(
                "insert into my_derby.race_program_source_2025("
                "source_date,source_meet,source_rc_no,source_rank,"
                "distance_m,source_runner_count,original_st_time,original_rc_name) values\n"
                + ",\n".join(parts)
                + "\non conflict(source_date,source_meet,source_rc_no)"
                " do update set source_rank=excluded.source_rank,"
                " distance_m=excluded.distance_m,"
                " source_runner_count=excluded.source_runner_count,"
                " original_st_time=excluded.original_st_time,"
                " original_rc_name=excluded.original_rc_name;\n"
            )
        f.write("""
-- Apply the imported dusu to every matching season programme race, including reused weeks.
update my_derby.races r
 set target_runner_count=s.source_runner_count,
     prize_policy=jsonb_set(r.prize_policy,'{source_dusu}',to_jsonb(s.source_runner_count),true)
from my_derby.race_program_source_2025 s
where r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  and (r.prize_policy->>'source_date')::date=s.source_date
  and r.prize_policy->>'source_meet'=s.source_meet
  and (r.prize_policy->>'source_rc_no')::int=s.source_rc_no;
""")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("ranked_schedule_import.sql"))
    arguments = parser.parse_args()
    items = parse_csv(arguments.source)
    export_sql(items, arguments.output)
    print(f"Created {arguments.output} from {len(items)} distinct races")
