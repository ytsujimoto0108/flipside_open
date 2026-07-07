import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import screen_outcomes


def write_rm5(
    directory: Path,
    filename: str,
    doi: str,
    title: str = "Example review",
    modified: str = "2022-09-30 12:34:56 +0000",
) -> Path:
    path = directory / filename
    path.write_text(
        (
            '<?xml version="1.0" encoding="UTF-8"?>'
            f'<COCHRANE_REVIEW DOI="{doi}" ID="review-1" '
            f'MODIFIED="{modified}" TYPE="INTERVENTION">'
            f"<COVER_SHEET><TITLE>{title}</TITLE></COVER_SHEET>"
            "</COCHRANE_REVIEW>"
        ),
        encoding="utf-8",
    )
    return path


class OutcomeNameClassificationTests(unittest.TestCase):
    def test_expected_death_and_survival_forms_match(self) -> None:
        names = ["Death", "Deaths", "Died", "All deaths", "Overall survival"]
        for name in names:
            with self.subTest(name=name):
                matched_term, status, _ = screen_outcomes.classify_outcome_name(name)
                self.assertIsNotNone(matched_term)
                self.assertEqual(status, "eligible")

    def test_ambiguous_non_target_forms_do_not_match(self) -> None:
        names = ["Non-fatal myocardial infarction", "CLD in survivors", "Response"]
        for name in names:
            with self.subTest(name=name):
                matched_term, status, reason = screen_outcomes.classify_outcome_name(name)
                self.assertIsNone(matched_term)
                self.assertEqual(status, "no_keyword")
                self.assertEqual(reason, "no_death_or_survival_term")

    def test_composite_and_multiple_timepoints_are_distinguished(self) -> None:
        _, composite_status, composite_reason = screen_outcomes.classify_outcome_name(
            "Death or myocardial infarction"
        )
        _, time_status, time_reason = screen_outcomes.classify_outcome_name(
            "Death at 30 days and 1 year"
        )

        self.assertEqual(composite_status, "composite")
        self.assertEqual(
            composite_reason, "death_term_directly_joined_to_other_component"
        )
        self.assertEqual(time_status, "eligible")
        self.assertEqual(time_reason, "multiple_timepoints")

    def test_uncertain_connector_requires_manual_review(self) -> None:
        _, status, reason = screen_outcomes.classify_outcome_name(
            "All-cause mortality - biomarkers or anthropometrics"
        )
        self.assertEqual(status, "needs_manual_review")
        self.assertEqual(reason, "ambiguous_connector")

    def test_reverse_and_or_composite_requires_manual_review(self) -> None:
        _, status, reason = screen_outcomes.classify_outcome_name(
            "Perioperative stroke and/or death"
        )
        self.assertEqual(status, "needs_manual_review")
        self.assertEqual(reason, "ambiguous_connector")

    def test_first_event_composite_is_excluded(self) -> None:
        _, status, reason = screen_outcomes.classify_outcome_name(
            "First event: death, hospital discharge, or 120 days after birth"
        )
        self.assertEqual(status, "composite")
        self.assertEqual(reason, "explicit_composite_marker")


class ReviewVersionTests(unittest.TestCase):
    def test_doi_title_and_timestamp_are_parsed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = write_rm5(
                Path(tmp),
                "review.rm5",
                "10.1002/14651858.CD015395.pub2",
                title="A review title",
            )
            doi_base, pub_no = screen_outcomes.parse_doi_pub(path)
            title, modified = screen_outcomes.get_title_and_modified(path)

        self.assertEqual(doi_base, "10.1002/14651858.CD015395")
        self.assertEqual(pub_no, 2)
        self.assertEqual(title, "A review title")
        self.assertIsNotNone(modified)
        self.assertEqual(modified.hour, 12)
        self.assertEqual(modified.minute, 34)

    def test_doi_without_publication_suffix_is_version_zero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = write_rm5(
                Path(tmp),
                "review.rm5",
                "10.1002/14651858.CD015395",
            )
            doi_base, pub_no = screen_outcomes.parse_doi_pub(path)

        self.assertEqual(doi_base, "10.1002/14651858.CD015395")
        self.assertEqual(pub_no, 0)

    def test_title_preserves_text_inside_subscript_elements(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = write_rm5(
                Path(tmp),
                "review.rm5",
                "",
                title="Long-acting beta<SUB>2</SUB>-agonist review",
            )
            title, _ = screen_outcomes.get_title_and_modified(path)

        self.assertEqual(title, "Long-acting beta2-agonist review")

    def test_latest_publication_number_is_selected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            write_rm5(
                directory,
                "base.rm5",
                "10.1002/14651858.CD015395",
            )
            write_rm5(
                directory,
                "pub2.rm5",
                "10.1002/14651858.CD015395.pub2",
            )
            latest = write_rm5(
                directory,
                "pub10.rm5",
                "10.1002/14651858.CD015395.pub10",
            )

            selected = screen_outcomes.select_latest_files(directory)

        self.assertEqual(selected, {latest})


if __name__ == "__main__":
    unittest.main()
