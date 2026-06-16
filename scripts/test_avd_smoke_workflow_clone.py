#!/usr/bin/env python3
import pathlib
import unittest


WORKFLOW = pathlib.Path(__file__).resolve().parents[1] / ".github" / "workflows" / "avd-smoke.yml"


class AvdSmokeWorkflowCloneTest(unittest.TestCase):
    def test_private_repo_checkout_uses_remote_tracking_ref(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(
            'git fetch origin "$TARGET_REF":"refs/remotes/origin/$TARGET_REF"',
            text,
            "workflow must fetch the private repo branch into a checkoutable remote-tracking ref",
        )
        self.assertIn(
            'git checkout -B "$TARGET_REF" "origin/$TARGET_REF"',
            text,
            "workflow must checkout the fetched remote-tracking ref explicitly",
        )


if __name__ == "__main__":
    unittest.main()
