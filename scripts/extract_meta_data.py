#!/usr/bin/env python3
"""Extract meta-analysis data and per-study 2x2 tables from screened rm5 files."""

from pathlib import Path
import csv
import re
import xml.etree.ElementTree as ET
from typing import Dict, List, Tuple, Set


SCREENING_CSV = Path(__file__).resolve().parent.parent / "data" / "screening_matches_v2.csv"
RM5_DIR = Path(__file__).resolve().parent.parent / "data" / "rm5"
OUTPUT_META = Path(__file__).resolve().parent.parent / "data" / "meta_analyses_extracted.csv"
OUTPUT_STUDIES = Path(__file__).resolve().parent.parent / "data" / "meta_analysis_studies.csv"

KEYWORDS = ["death", "deaths", "died", "dead", "mortality", "fatality", "fatalities", "alive", "survival"]


def clean_text(value: str) -> str:
    """Remove internal newlines/tabs and trim spaces to keep CSV line counts stable."""
    return " ".join((value or "").strip().split())


def safe_int(value: str) -> int:
    try:
        return int(value)
    except Exception:
        return 0


def classify_outcome(name: str) -> str:
    """Return a coarse outcome class: 'mortality', 'survival', or 'unspecified'."""
    lower = name.lower()
    for kw in KEYWORDS:
        if kw in lower:
            if kw in {"alive", "survival"}:
                return "survival"
            return "mortality"
    return "unspecified"


def load_screened() -> Dict[str, Set[Tuple[str, str, str]]]:
    """Load screening_matches_v2.csv and return mapping rm5_file -> set of (id, name, measure)."""
    mapping: Dict[str, Set[Tuple[str, str, str]]] = {}
    with SCREENING_CSV.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rm5 = row["rm5_file"]
            key = (
                row["comparison_id"],
                clean_text(row["outcome_name"]),
                row["effect_measure"],
            )
            mapping.setdefault(rm5, set()).add(key)
    return mapping


def extract_review_metadata(root: ET.Element) -> Dict[str, str]:
    """Extract bibliographic metadata from rm5 root."""
    return {
        "review_id": root.attrib.get("ID", ""),
        "doi": root.attrib.get("DOI", ""),
        "review_no": root.attrib.get("REVIEW_NO", ""),
    }


def extract_pub_info(root: ET.Element) -> Dict[str, str]:
    """Extract publication issue/year if present."""
    info = {"review_published_issue": "", "review_published_year": ""}
    for elem in root.iter():
        if elem.tag == "REVIEW_PUBLISHED":
            info["review_published_issue"] = elem.attrib.get("ISSUE", "") or ""
            info["review_published_year"] = elem.attrib.get("YEAR", "") or ""
            break
    return info


def main() -> None:
    screened = load_screened()
    if not screened:
        raise SystemExit("screening_matches_v2.csv is empty; run the screening script first.")

    meta_rows: List[Dict[str, str]] = []
    study_rows: List[Dict[str, str]] = []

    for rm5_file, target_keys in screened.items():
        path = RM5_DIR / rm5_file
        if not path.exists():
            print(f"Warning: {rm5_file} not found; skipping")
            continue

        tree = ET.parse(path)
        root = tree.getroot()
        review_meta = extract_review_metadata(root)
        review_meta.update(extract_pub_info(root))
        review_title_elem = root.find(".//TITLE")
        review_title = (review_title_elem.text or "").strip() if review_title_elem is not None else ""

        for elem in root.findall(".//DICH_OUTCOME"):
            outcome_id = elem.attrib.get("ID", "")
            outcome_name = clean_text(elem.findtext("NAME") or "")
            effect_measure = (elem.attrib.get("EFFECT_MEASURE") or "").upper()
            key = (outcome_id, outcome_name, effect_measure)
            if key not in target_keys:
                continue

            method = elem.attrib.get("METHOD", "")
            random = elem.attrib.get("RANDOM", "")
            group_label_1 = elem.findtext("GROUP_LABEL_1") or ""
            group_label_2 = elem.findtext("GROUP_LABEL_2") or ""
            graph_label_1 = elem.findtext("GRAPH_LABEL_1") or ""
            graph_label_2 = elem.findtext("GRAPH_LABEL_2") or ""
            outcome_class = classify_outcome(outcome_name)
            p_value_attr = elem.attrib.get("P_Z", "")
            try:
                p_value = float(p_value_attr)
            except Exception:
                p_value = None
            is_significant_05 = "YES" if p_value is not None and p_value < 0.05 else "NO"

            # Meta-level totals/events and aggregate CER for fallback/reference
            meta_events_1 = safe_int(elem.attrib.get("EVENTS_1", "0"))
            meta_events_2 = safe_int(elem.attrib.get("EVENTS_2", "0"))
            meta_total_1 = safe_int(elem.attrib.get("TOTAL_1", "0"))
            meta_total_2 = safe_int(elem.attrib.get("TOTAL_2", "0"))
            total_participants = meta_total_1 + meta_total_2
            total_events = meta_events_1 + meta_events_2
            aggregate_control_event_rate = meta_events_2 / meta_total_2 if meta_total_2 else None

            study_nodes = elem.findall("DICH_DATA")
            has_single_zero = False
            has_double_zero = False
            for data in study_nodes:
                e1 = safe_int(data.attrib.get("EVENTS_1", "0"))
                e2 = safe_int(data.attrib.get("EVENTS_2", "0"))
                if e1 == 0 and e2 == 0:
                    has_double_zero = True
                elif (e1 == 0) != (e2 == 0):
                    has_single_zero = True

            meta_rows.append(
                {
                    "rm5_file": rm5_file,
                    "review_title": review_title,
                    **review_meta,
                    "comparison_id": outcome_id,
                    "outcome_name": outcome_name,
                    "outcome_class": outcome_class,
                    "effect_measure": effect_measure,
                    "method": method,
                    "random": random,
                    "group_label_1": group_label_1,
                    "group_label_2": group_label_2,
                    "graph_label_1": graph_label_1,
                    "graph_label_2": graph_label_2,
                    "meta_events_1": meta_events_1,
                    "meta_events_2": meta_events_2,
                    "meta_total_1": meta_total_1,
                    "meta_total_2": meta_total_2,
                    "total_participants": total_participants,
                    "total_events": total_events,
                    "aggregate_control_event_rate": aggregate_control_event_rate
                    if aggregate_control_event_rate is not None
                    else "",
                    "p_value": p_value if p_value is not None else "",
                    "is_significant_05": is_significant_05,
                    "has_single_zero_study": "YES" if has_single_zero else "NO",
                    "has_double_zero_study": "YES" if has_double_zero else "NO",
                    "num_studies": len(study_nodes),
                }
            )

            for data in study_nodes:
                study_rows.append(
                    {
                        "rm5_file": rm5_file,
                        "comparison_id": outcome_id,
                        "outcome_name": outcome_name,
                        "study_id": data.attrib.get("STUDY_ID", ""),
                        "events_1": data.attrib.get("EVENTS_1", ""),
                        "events_2": data.attrib.get("EVENTS_2", ""),
                        "total_1": data.attrib.get("TOTAL_1", ""),
                        "total_2": data.attrib.get("TOTAL_2", ""),
                        "order": data.attrib.get("ORDER", ""),
                        "var": data.attrib.get("VAR", data.attrib.get("VARIANCE", "")),
                        "weight": data.attrib.get("WEIGHT", ""),
                    }
                )

    OUTPUT_META.parent.mkdir(parents=True, exist_ok=True)
    meta_fields = [
        "rm5_file",
        "review_id",
        "doi",
        "review_no",
        "review_published_issue",
        "review_published_year",
        "review_title",
        "comparison_id",
        "outcome_name",
        "outcome_class",
        "effect_measure",
        "method",
        "random",
        "group_label_1",
        "group_label_2",
        "graph_label_1",
        "graph_label_2",
        "meta_events_1",
        "meta_events_2",
        "meta_total_1",
        "meta_total_2",
        "total_participants",
        "total_events",
        "aggregate_control_event_rate",
        "p_value",
        "is_significant_05",
        "has_single_zero_study",
        "has_double_zero_study",
        "num_studies",
    ]
    with OUTPUT_META.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=meta_fields)
        writer.writeheader()
        cleaned_meta = [
            {k: clean_text(v) if isinstance(v, str) else v for k, v in row.items()}
            for row in meta_rows
        ]
        writer.writerows(cleaned_meta)

    study_fields = [
        "rm5_file",
        "comparison_id",
        "outcome_name",
        "study_id",
        "events_1",
        "events_2",
        "total_1",
        "total_2",
        "order",
        "var",
        "weight",
    ]
    with OUTPUT_STUDIES.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=study_fields)
        writer.writeheader()
        cleaned_studies = [
            {k: clean_text(v) if isinstance(v, str) else v for k, v in row.items()}
            for row in study_rows
        ]
        writer.writerows(cleaned_studies)

    print(f"Wrote {len(meta_rows)} meta-analyses to {OUTPUT_META}")
    print(f"Wrote {len(study_rows)} study-level rows to {OUTPUT_STUDIES}")


if __name__ == "__main__":
    main()
