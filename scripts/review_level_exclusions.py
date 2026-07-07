#!/usr/bin/env python3

import sys
from pathlib import Path
import csv
import xml.etree.ElementTree as ET
from typing import Dict, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from screen_outcomes import (
    V2_OUTCOME_TERM_PATTERN,
    classify_outcome_name,
    get_complete_2x2_nodes,
    get_reported_num_studies,
    select_latest_files,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
RM5_DIR = REPO_ROOT / "data" / "rm5"
SCREENING_CSV = REPO_ROOT / "data" / "screening_matches_v2.csv"
AUDIT_CSV = REPO_ROOT / "data" / "screening_audit_v2.csv"
OUTPUT_CSV = REPO_ROOT / "data" / "results" / "review_exclusion_breakdown.csv"

STAGE_LABELS = {
    0: "no_dichotomous_outcome",
    1: "not_or_rr_or_not_estimable",
    2: "no_keyword",
    3: "composite",
    4: "missing_2x2",
    5: "num_studies_le1",
    6: "manual_exclusion",
}


def load_final_decisions() -> Dict[Tuple[str, str], str]:
    """Map (rm5_file, comparison_id) -> final_included ('YES'/'NO') from the v2 audit trail."""
    with AUDIT_CSV.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        return {
            (row["rm5_file"], row["comparison_id"]): row["final_included"]
            for row in reader
        }


def outcome_stage(elem: ET.Element, rm5_file: str, final_decisions: Dict[Tuple[str, str], str]) -> int:
    """Return the furthest v2 screening stage (1-6) reached by this outcome entry."""
    measure = (elem.attrib.get("EFFECT_MEASURE") or "").upper()
    estimable = (elem.attrib.get("ESTIMABLE") or "").upper() == "YES"
    if measure not in {"OR", "RR"} or not estimable:
        return 1

    outcome_name = (elem.findtext("NAME") or "").strip()
    if not V2_OUTCOME_TERM_PATTERN.search(outcome_name):
        return 2

    _, composite_status, _ = classify_outcome_name(outcome_name)
    if composite_status == "composite":
        return 3

    if not get_complete_2x2_nodes(elem):
        return 4
    if get_reported_num_studies(elem) <= 1:
        return 5

    if composite_status == "needs_manual_review":
        comparison_id = elem.attrib.get("ID", "")
        final_included = final_decisions.get((rm5_file, comparison_id))
        if final_included == "YES":
            return 7  # would qualify -- should not occur for excluded reviews
        return 6

    return 7  # would qualify -- should not occur for excluded reviews


def included_file_names() -> set:
    with SCREENING_CSV.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        return {row["rm5_file"] for row in reader}


def main() -> None:
    final_decisions = load_final_decisions()
    excluded = [p for p in select_latest_files(RM5_DIR) if p.name not in included_file_names()]

    counts = {stage: 0 for stage in STAGE_LABELS}
    for path in excluded:
        tree = ET.parse(path)
        root = tree.getroot()
        max_stage = 0
        for elem in root.findall(".//DICH_OUTCOME"):
            stage = outcome_stage(elem, path.name, final_decisions)
            if stage > max_stage:
                max_stage = stage
        if max_stage == 7:
            raise RuntimeError(f"{path.name}: excluded review unexpectedly has a qualifying outcome")
        counts[max_stage] += 1

    print(f"Excluded reviews: {len(excluded)}")
    for stage, label in STAGE_LABELS.items():
        print(f"  {label}: {counts[stage]}")

    OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_CSV.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["stage", "reason", "n_reviews"])
        for stage, label in STAGE_LABELS.items():
            writer.writerow([stage, label, counts[stage]])
    print(f"Wrote: {OUTPUT_CSV}")


if __name__ == "__main__":
    main()
