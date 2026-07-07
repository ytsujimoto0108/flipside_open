#!/usr/bin/env python3
"""Combine automatic screening candidates with completed manual adjudications."""

from pathlib import Path
import argparse
import csv
from typing import Dict, Iterable, List, Sequence, Tuple


ScreeningKey = Tuple[str, str]
MATCH_FIELDS = [
    "rm5_file",
    "review_id",
    "review_title",
    "comparison_id",
    "effect_measure",
    "outcome_name",
]
FINAL_AUDIT_FIELDS = [
    "manual_decision",
    "reviewer_notes",
    "final_included",
    "final_exclusion_reason",
]


def screening_key(row: Dict[str, str]) -> ScreeningKey:
    """Return the stable key shared by candidate and adjudication files."""
    return (
        (row.get("rm5_file") or "").strip(),
        (row.get("comparison_id") or "").strip(),
    )


def read_csv(path: Path, required_fields: Iterable[str]) -> Tuple[List[str], List[Dict[str, str]]]:
    """Read a UTF-8 CSV and verify its required columns."""
    if not path.exists():
        raise ValueError(f"Input file does not exist: {path}")
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames or []
        missing = sorted(set(required_fields) - set(fieldnames))
        if missing:
            raise ValueError(f"Missing columns in {path}: {', '.join(missing)}")
        return fieldnames, list(reader)


def index_unique(rows: Sequence[Dict[str, str]], label: str) -> Dict[ScreeningKey, Dict[str, str]]:
    """Index rows by stable key and reject empty or duplicate identifiers."""
    indexed: Dict[ScreeningKey, Dict[str, str]] = {}
    for row_number, row in enumerate(rows, start=2):
        key = screening_key(row)
        if not all(key):
            raise ValueError(f"Empty screening key in {label}, row {row_number}: {key}")
        if key in indexed:
            raise ValueError(f"Duplicate screening key in {label}: {key}")
        indexed[key] = row
    return indexed


def validate_adjudications(
    candidate_rows: Sequence[Dict[str, str]],
    adjudication_rows: Sequence[Dict[str, str]],
) -> Dict[ScreeningKey, Dict[str, str]]:
    """Require exactly one completed decision for every manual-review candidate."""
    candidate_by_key = index_unique(candidate_rows, "candidate file")
    adjudication_by_key = index_unique(adjudication_rows, "adjudication file")
    expected_keys = {
        key
        for key, row in candidate_by_key.items()
        if (row.get("automatic_decision") or "").strip().lower() == "manual_review"
    }
    actual_keys = set(adjudication_by_key)
    missing = sorted(expected_keys - actual_keys)
    extra = sorted(actual_keys - expected_keys)
    if missing or extra:
        details = []
        if missing:
            details.append(f"missing={len(missing)} (e.g. {missing[:3]})")
        if extra:
            details.append(f"extra={len(extra)} (e.g. {extra[:3]})")
        raise ValueError("Adjudication keys do not match manual-review candidates: " + "; ".join(details))

    for key, row in adjudication_by_key.items():
        decision = (row.get("manual_decision") or "").strip().lower()
        if decision not in {"include", "exclude"}:
            raise ValueError(
                f"manual_decision must be include or exclude for {key}; got {decision!r}"
            )
        row["manual_decision"] = decision
    return adjudication_by_key


def finalize_rows(
    candidate_rows: Sequence[Dict[str, str]],
    adjudication_rows: Sequence[Dict[str, str]],
) -> Tuple[List[Dict[str, str]], List[Dict[str, str]]]:
    """Apply automatic and manual decisions and return matches plus an audit table."""
    adjudication_by_key = validate_adjudications(candidate_rows, adjudication_rows)
    final_matches: List[Dict[str, str]] = []
    audit_rows: List[Dict[str, str]] = []

    for candidate in candidate_rows:
        key = screening_key(candidate)
        automatic_decision = (candidate.get("automatic_decision") or "").strip().lower()
        if automatic_decision not in {"include", "exclude", "manual_review"}:
            raise ValueError(
                f"Invalid automatic_decision for {key}: {automatic_decision!r}"
            )

        adjudication = adjudication_by_key.get(key, {})
        manual_decision = adjudication.get("manual_decision", "")
        reviewer_notes = adjudication.get("reviewer_notes", "")
        if automatic_decision == "include" or manual_decision == "include":
            final_included = "YES"
            final_exclusion_reason = ""
        elif automatic_decision == "exclude":
            final_included = "NO"
            final_exclusion_reason = candidate.get("exclusion_reason", "") or "automatic_exclusion"
        else:
            final_included = "NO"
            final_exclusion_reason = "manual_exclusion"

        audit_row = dict(candidate)
        audit_row.update(
            {
                "manual_decision": manual_decision,
                "reviewer_notes": reviewer_notes,
                "final_included": final_included,
                "final_exclusion_reason": final_exclusion_reason,
            }
        )
        audit_rows.append(audit_row)
        if final_included == "YES":
            final_matches.append({field: candidate.get(field, "") for field in MATCH_FIELDS})

    return final_matches, audit_rows


def write_csv(path: Path, fieldnames: Sequence[str], rows: Sequence[Dict[str, str]]) -> None:
    """Write a UTF-8 CSV with a fixed column order."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    """Parse command-line arguments and write final screening datasets."""
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--candidates",
        type=Path,
        default=repo_root / "data" / "screening_candidates_v2.csv",
    )
    parser.add_argument(
        "--adjudications",
        type=Path,
        default=repo_root / "data" / "screening_adjudication_v2.csv",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "data" / "screening_matches_v2.csv",
    )
    parser.add_argument(
        "--audit-output",
        type=Path,
        default=repo_root / "data" / "screening_audit_v2.csv",
    )
    args = parser.parse_args()

    candidate_fields, candidate_rows = read_csv(
        args.candidates,
        required_fields={*MATCH_FIELDS, "automatic_decision", "exclusion_reason"},
    )
    _, adjudication_rows = read_csv(
        args.adjudications,
        required_fields={"rm5_file", "comparison_id", "manual_decision"},
    )
    final_rows, audit_rows = finalize_rows(candidate_rows, adjudication_rows)
    write_csv(args.output, MATCH_FIELDS, final_rows)
    write_csv(args.audit_output, candidate_fields + FINAL_AUDIT_FIELDS, audit_rows)

    automatic_counts: Dict[str, int] = {}
    for row in candidate_rows:
        decision = row["automatic_decision"].strip().lower()
        automatic_counts[decision] = automatic_counts.get(decision, 0) + 1
    manual_counts: Dict[str, int] = {}
    for row in adjudication_rows:
        decision = row["manual_decision"]
        manual_counts[decision] = manual_counts.get(decision, 0) + 1

    print(f"Wrote {len(final_rows)} final matches to {args.output}")
    print(f"Wrote {len(audit_rows)} audit rows to {args.audit_output}")
    print("Automatic decisions:", automatic_counts)
    print("Manual decisions:", manual_counts)


if __name__ == "__main__":
    main()
