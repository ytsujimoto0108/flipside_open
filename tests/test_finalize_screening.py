import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import finalize_screening


def candidate(comparison_id: str, decision: str, reason: str = "") -> dict:
    return {
        "rm5_file": "review.rm5",
        "review_id": "review-1",
        "review_title": "Example review",
        "comparison_id": comparison_id,
        "effect_measure": "RR",
        "outcome_name": f"Outcome {comparison_id}",
        "automatic_decision": decision,
        "exclusion_reason": reason,
    }


class FinalizeScreeningTests(unittest.TestCase):
    def test_applies_automatic_and_manual_decisions(self) -> None:
        candidates = [
            candidate("include", "include"),
            candidate("exclude", "exclude", "composite_outcome"),
            candidate("manual", "manual_review"),
        ]
        adjudications = [
            {
                "rm5_file": "review.rm5",
                "comparison_id": "manual",
                "manual_decision": " INCLUDE ",
                "reviewer_notes": "single outcome",
            }
        ]

        matches, audit = finalize_screening.finalize_rows(
            candidates, adjudications
        )

        self.assertEqual(
            [row["comparison_id"] for row in matches], ["include", "manual"]
        )
        self.assertEqual(
            [row["final_included"] for row in audit], ["YES", "NO", "YES"]
        )
        self.assertEqual(audit[1]["final_exclusion_reason"], "composite_outcome")
        self.assertEqual(audit[2]["manual_decision"], "include")

    def test_rejects_missing_adjudication(self) -> None:
        candidates = [candidate("manual", "manual_review")]
        with self.assertRaisesRegex(ValueError, "missing=1"):
            finalize_screening.finalize_rows(candidates, [])

    def test_rejects_extra_adjudication(self) -> None:
        candidates = [candidate("automatic", "include")]
        adjudications = [
            {
                "rm5_file": "review.rm5",
                "comparison_id": "unexpected",
                "manual_decision": "exclude",
            }
        ]
        with self.assertRaisesRegex(ValueError, "extra=1"):
            finalize_screening.finalize_rows(candidates, adjudications)

    def test_rejects_blank_or_invalid_manual_decision(self) -> None:
        candidates = [candidate("manual", "manual_review")]
        adjudications = [
            {
                "rm5_file": "review.rm5",
                "comparison_id": "manual",
                "manual_decision": "",
            }
        ]
        with self.assertRaisesRegex(ValueError, "must be include or exclude"):
            finalize_screening.finalize_rows(candidates, adjudications)

    def test_rejects_duplicate_keys(self) -> None:
        duplicate = candidate("same", "include")
        with self.assertRaisesRegex(ValueError, "Duplicate screening key"):
            finalize_screening.finalize_rows([duplicate, dict(duplicate)], [])

    def test_screening_key_does_not_depend_on_outcome_name_encoding(self) -> None:
        base = {"rm5_file": "review.rm5", "comparison_id": "CMP-001.01"}
        first = {**base, "outcome_name": "Mortality at ≤1 month"}
        second = {**base, "outcome_name": "Mortality at 1 month"}

        self.assertEqual(
            finalize_screening.screening_key(first),
            finalize_screening.screening_key(second),
        )


if __name__ == "__main__":
    unittest.main()
