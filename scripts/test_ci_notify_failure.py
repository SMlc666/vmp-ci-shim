#!/usr/bin/env python3
import pathlib
import unittest


WORKFLOW = pathlib.Path(__file__).resolve().parents[1] / ".github" / "workflows" / "ci.yml"


class NotifyFailureWorkflowTest(unittest.TestCase):
    def test_notify_failure_is_guarded_with_always(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("notify_failure:", text)
        self.assertIn(
            "if: ${{ always() && (needs.e2e_plan.result == 'failure' || needs.public_demo.result == 'failure' || needs.glibc_unit.result == 'failure' || needs.csharp_glibc_unit.result == 'failure' || needs.bionic_unit.result == 'failure' || needs.glibc_e2e.result == 'failure' || needs.bionic_e2e.result == 'failure') }}",
            text,
            "notify_failure must force condition evaluation after layered job failures",
        )
        self.assertIn("CSHARP_GLIBC_UNIT: ${{ needs.csharp_glibc_unit.result }}", text)


if __name__ == "__main__":
    unittest.main()
