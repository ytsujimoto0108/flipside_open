#!/usr/bin/env python3
"""Screen RevMan 5 (.rm5) files for dichotomous outcomes with death/survival keywords."""

from pathlib import Path
import argparse
import csv
import re
import xml.etree.ElementTree as ET
from datetime import datetime
from typing import Dict, Iterator, List, Optional, Tuple, Set


# V2 expands only unambiguous lexical forms. "fatal" and "survivor(s)" are
# intentionally omitted because they commonly describe non-fatal outcomes or
# outcomes measured only among survivors.
V2_OUTCOME_TERM = r"(?:deaths?|died|dead|mortality|fatalit(?:y|ies)|alive|survival)"
V2_OUTCOME_TERM_PATTERN = re.compile(
    rf"\b(?P<term>{V2_OUTCOME_TERM})\b",
    flags=re.IGNORECASE,
)
V2_COMPLEMENTARY_PAIR_PATTERN = re.compile(
    r"\b(?:deaths?|died|dead|mortality|fatalit(?:y|ies))\b\s*/\s*"
    r"\b(?:alive|survival)\b"
    r"|\b(?:alive|survival)\b\s*/\s*"
    r"\b(?:deaths?|died|dead|mortality|fatalit(?:y|ies))\b",
    flags=re.IGNORECASE,
)
V2_EXPLICIT_COMPOSITE_PATTERN = re.compile(
    r"\b(?:composite|morbidity|serious adverse events?|sae|first event)\b",
    flags=re.IGNORECASE,
)
V2_DIRECT_COMPOSITE_PATTERN = re.compile(
    rf"\b{V2_OUTCOME_TERM}\b\s*(?:and/or|or|and|/)\s*"
    r"(?!at\b|by\b|before\b|after\b|during\b|within\b|\d)",
    flags=re.IGNORECASE,
)
V2_CONNECTOR_PATTERN = re.compile(
    r"\s(?:and/or|or|and|/)\s",
    flags=re.IGNORECASE,
)
V2_TEMPORAL_CONTINUATION_PATTERN = re.compile(
    r"\s*(?:(?:at|by|before|after|during|within)\s+)?"
    r"(?:\d+(?:\.\d+)?\s*(?:hours?|days?|weeks?|months?|years?|yrs?)\b"
    r"|discharge\b|end of follow-up\b)",
    flags=re.IGNORECASE,
)


def clean_text(value: str) -> str:
    """Remove internal newlines/tabs and trim spaces to keep CSV line counts stable."""
    return " ".join((value or "").strip().split())


def classify_outcome_name(name: str) -> Tuple[Optional[str], str, str]:
    """Classify a name as eligible, composite, manual review, or no keyword."""
    normalized = clean_text(name)
    match = V2_OUTCOME_TERM_PATTERN.search(normalized)
    if not match:
        return None, "no_keyword", "no_death_or_survival_term"

    matched_term = match.group("term")
    if V2_COMPLEMENTARY_PAIR_PATTERN.search(normalized):
        return matched_term, "eligible", "complementary_pair_label"
    if V2_EXPLICIT_COMPOSITE_PATTERN.search(normalized):
        return matched_term, "composite", "explicit_composite_marker"
    if V2_DIRECT_COMPOSITE_PATTERN.search(normalized):
        return matched_term, "composite", "death_term_directly_joined_to_other_component"

    connectors = list(V2_CONNECTOR_PATTERN.finditer(normalized))
    if not connectors:
        return matched_term, "eligible", "no_composite_connector"
    if all(
        V2_TEMPORAL_CONTINUATION_PATTERN.match(normalized[connector.end() :])
        for connector in connectors
    ):
        return matched_term, "eligible", "multiple_timepoints"
    return matched_term, "needs_manual_review", "ambiguous_connector"


def get_title_and_modified(path: Path) -> Tuple[str, Optional[datetime]]:
    """Extract review title and modified timestamp (if available) from rm5 file."""
    context = ET.iterparse(path, events=("start", "end"))
    _, root = next(context)
    title = ""
    modified_raw = root.attrib.get("MODIFIED")

    for event, elem in context:
        if event != "end":
            continue
        if event == "end" and elem.tag == "TITLE" and not title:
            title = clean_text("".join(elem.itertext()))
            break

    root.clear()

    modified_dt: Optional[datetime] = None
    if modified_raw:
        try:
            modified_dt = datetime.fromisoformat(modified_raw.replace("Z", "+00:00"))
        except Exception:
            modified_dt = None

    return title, modified_dt


def parse_doi_pub(path: Path) -> Tuple[Optional[str], Optional[int]]:
    """Extract DOI base and pub number (if available) from rm5 root."""
    try:
        context = ET.iterparse(path, events=("start",))
        _, root = next(context)
        doi = root.attrib.get("DOI") or ""
    except Exception:
        return None, None
    finally:
        try:
            root.clear()
        except Exception:
            pass

    # Example: 10.1002/14651858.CD015395.pub2 -> base: 10.1002/14651858.CD015395, pub: 2
    m = re.match(r"^(10\.1002/14651858\.[^.]+?)(?:\.pub(\d+))?$", doi)
    if not m:
        return None, None
    return m.group(1), int(m.group(2) or 0)


def select_latest_files(rm5_dir: Path) -> Set[Path]:
    """Select the latest rm5 file for each normalized DOI or review title."""
    doi_map: Dict[str, Tuple[Path, int, Optional[datetime]]] = {}
    title_map: Dict[str, Tuple[Path, Optional[datetime]]] = {}

    for rm5_file in sorted(rm5_dir.glob("*.rm5")):
        doi_base, pub_no = parse_doi_pub(rm5_file)
        title, modified = get_title_and_modified(rm5_file)

        if doi_base:
            current = doi_map.get(doi_base)
            if current is None or (pub_no is not None and pub_no > current[1]) or (
                pub_no == current[1]
                and modified is not None
                and (current[2] is None or modified > current[2])
            ):
                doi_map[doi_base] = (rm5_file, pub_no or 0, modified)
        else:
            key = title.lower() if title else rm5_file.stem.lower()
            current = title_map.get(key)
            if current is None or (
                modified is not None and (current[1] is None or modified > current[1])
            ):
                title_map[key] = (rm5_file, modified)

    return {path for path, _, _ in doi_map.values()} | {
        path for path, _ in title_map.values()
    }


def get_complete_2x2_nodes(elem: ET.Element) -> List[ET.Element]:
    """Return study nodes containing all four values needed for a 2x2 table."""
    return [
        node
        for node in elem.findall("DICH_DATA")
        if all(
            node.attrib.get(attr) not in {None, ""}
            for attr in ("EVENTS_1", "EVENTS_2", "TOTAL_1", "TOTAL_2")
        )
    ]


def get_reported_num_studies(elem: ET.Element) -> int:
    """Read the reported study count, falling back to the number of study nodes."""
    data_nodes = elem.findall("DICH_DATA")
    value = elem.attrib.get("STUDIES")
    try:
        return int(value) if value is not None else len(data_nodes)
    except ValueError:
        return len(data_nodes)


def iter_v2_candidates(path: Path) -> Iterator[Dict[str, object]]:
    """Yield auditable V2 screening records for expanded keyword matches."""
    root = ET.parse(path).getroot()
    review_type = (root.attrib.get("TYPE") or "").upper()
    if review_type and review_type != "INTERVENTION":
        return

    review_id = root.attrib.get("ID", "")
    title_elem = root.find("./COVER_SHEET/TITLE")
    if title_elem is None:
        title_elem = root.find(".//TITLE")
    review_title = (
        clean_text("".join(title_elem.itertext())) if title_elem is not None else ""
    )

    for elem in root.findall(".//DICH_OUTCOME"):
        measure = (elem.attrib.get("EFFECT_MEASURE") or "").upper()
        estimable = (elem.attrib.get("ESTIMABLE") or "").upper() == "YES"
        if measure not in {"OR", "RR"} or not estimable:
            continue

        outcome_name = clean_text(elem.findtext("NAME") or "")
        matched_term, composite_status, classification_reason = classify_outcome_name(
            outcome_name
        )
        if matched_term is None:
            continue

        complete_2x2_studies = len(get_complete_2x2_nodes(elem))
        reported_num_studies = get_reported_num_studies(elem)

        if composite_status == "composite":
            automatic_decision = "exclude"
            exclusion_reason = "composite_outcome"
        elif complete_2x2_studies == 0:
            automatic_decision = "exclude"
            exclusion_reason = "missing_2x2"
        elif reported_num_studies <= 1:
            automatic_decision = "exclude"
            exclusion_reason = "num_studies_le1"
        elif composite_status == "needs_manual_review":
            automatic_decision = "manual_review"
            exclusion_reason = ""
        else:
            automatic_decision = "include"
            exclusion_reason = ""

        yield {
            "rm5_file": path.name,
            "review_id": review_id,
            "review_title": review_title,
            "comparison_id": elem.attrib.get("ID", ""),
            "effect_measure": measure,
            "estimable": "YES",
            "outcome_name": outcome_name,
            "matched_term": matched_term,
            "composite_status": composite_status,
            "classification_reason": classification_reason,
            "complete_2x2_studies": complete_2x2_studies,
            "reported_num_studies": reported_num_studies,
            "has_complete_2x2": "YES" if complete_2x2_studies > 0 else "NO",
            "num_studies_eligible": "YES" if reported_num_studies > 1 else "NO",
            "automatic_decision": automatic_decision,
            "exclusion_reason": exclusion_reason,
        }


CANDIDATE_FIELDS = [
    "rm5_file",
    "review_id",
    "review_title",
    "comparison_id",
    "effect_measure",
    "estimable",
    "outcome_name",
    "matched_term",
    "composite_status",
    "classification_reason",
    "complete_2x2_studies",
    "reported_num_studies",
    "has_complete_2x2",
    "num_studies_eligible",
    "automatic_decision",
    "exclusion_reason",
]
ADJUDICATION_FIELDS = [
    "rm5_file",
    "review_id",
    "review_title",
    "comparison_id",
    "outcome_name",
    "matched_term",
    "composite_status",
    "classification_reason",
    "automatic_decision",
    "manual_decision",
    "reviewer_notes",
]


def write_dict_rows(path: Path, fieldnames: List[str], rows: List[Dict[str, object]]) -> None:
    """Write dictionaries to a UTF-8 CSV with a fixed column order."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def run_screening(
    rm5_dir: Path,
    candidate_path: Path,
    adjudication_template_path: Path,
) -> None:
    """Create automatic screening candidates and a blank adjudication template."""
    latest_files = select_latest_files(rm5_dir)
    records: List[Dict[str, object]] = []
    for rm5_file in sorted(latest_files):
        records.extend(iter_v2_candidates(rm5_file))

    adjudication_rows: List[Dict[str, object]] = []
    for record in records:
        if record["automatic_decision"] != "manual_review":
            continue
        adjudication_row = {
            field: record.get(field, "")
            for field in ADJUDICATION_FIELDS
            if field not in {"manual_decision", "reviewer_notes"}
        }
        adjudication_row["manual_decision"] = ""
        adjudication_row["reviewer_notes"] = ""
        adjudication_rows.append(adjudication_row)

    write_dict_rows(candidate_path, CANDIDATE_FIELDS, records)
    write_dict_rows(
        adjudication_template_path,
        ADJUDICATION_FIELDS,
        adjudication_rows,
    )

    decision_counts: Dict[str, int] = {}
    for record in records:
        decision = str(record["automatic_decision"])
        decision_counts[decision] = decision_counts.get(decision, 0) + 1

    print(f"Wrote {len(records)} screening candidates to {candidate_path}")
    print(
        f"Wrote {len(adjudication_rows)} blank manual-review rows to "
        f"{adjudication_template_path}"
    )
    print("Automatic decisions:", decision_counts)


def main() -> None:
    """Parse command-line arguments and run automatic screening."""
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rm5-dir",
        type=Path,
        default=repo_root / "data" / "rm5",
        help="directory containing RevMan 5 files",
    )
    parser.add_argument(
        "--candidate-output",
        type=Path,
        default=repo_root / "data" / "screening_candidates_v2.csv",
        help="output path for all automatic screening candidates",
    )
    parser.add_argument(
        "--adjudication-template-output",
        type=Path,
        default=repo_root / "data" / "screening_adjudication_template_v2.csv",
        help="output path for the blank manual-adjudication template",
    )
    args = parser.parse_args()
    run_screening(
        args.rm5_dir,
        args.candidate_output,
        args.adjudication_template_output,
    )


if __name__ == "__main__":
    main()
