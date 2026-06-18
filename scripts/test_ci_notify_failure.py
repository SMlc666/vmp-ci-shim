#!/usr/bin/env python3
import pathlib
import unittest


WORKFLOW = pathlib.Path(__file__).resolve().parents[1] / ".github" / "workflows" / "ci.yml"


class NotifyFailureWorkflowTest(unittest.TestCase):
    def test_notify_failure_is_guarded_with_always(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("notify_failure:", text)
        self.assertIn(
            "if: ${{ always() && (needs.private_glibc.result == 'failure' || needs.private_bionic.outputs.result == 'failure') }}",
            text,
            "notify_failure must force condition evaluation after upstream job failures",
        )


if __name__ == "__main__":
    unittest.main()
