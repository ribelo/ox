#!/usr/bin/env python3
"""^nlintcov-8g4p: structural documentation evidence and non-documentation holes."""

import contextlib
import io
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch


CENSUS = Path(__file__).with_name("coverage.py")


class CoverageFixtures(unittest.TestCase):
    def census(self, sources, dune_files=None):
        with tempfile.TemporaryDirectory(prefix="ox-lint-coverage-") as directory:
            root = Path(directory)
            for path in sources:
                source = root / path
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text("let historical_value = 1\n")
            for path, text in (dune_files or {}).items():
                dune = root / path
                dune.parent.mkdir(parents=True, exist_ok=True)
                dune.write_text(text)
            inventory = root / "inventory.jsonl"
            inventory.write_text("".join(
                str(root / path) + "\t" + status + "\t" + reason
                + "\n" for path, (status, reason) in sources.items()
            ))

            def git(command, **kwargs):
                if kwargs.get("text"):
                    self.assertEqual(command, ["git", "-C", str(root), "rev-parse",
                                               "--show-toplevel"])
                    return str(root) + "\n"
                self.assertEqual(command, ["git", "-C", str(root), "ls-files", "-z",
                                           "--", "*.ml", "*.mli"])
                return "".join(path + "\0" for path in sources).encode()

            output, errors = io.StringIO(), io.StringIO()
            argv = [str(CENSUS), "unused-engine", str(root), "--inventory", str(inventory),
                    "--scan-exit", "0"]
            with patch.object(sys, "argv", argv), patch("subprocess.check_output", git), \
                    contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                try:
                    runpy.run_path(str(CENSUS), run_name="__main__")
                except SystemExit as exit:
                    return exit.code, output.getvalue(), errors.getvalue()
            return 0, output.getvalue(), errors.getvalue()

    def test_unexpected_documentation_directory_is_evidence(self):
        rc, output, errors = self.census({
            "docs/issues/history/acceptance/live/frozen.ml": ("excluded", "not-built"),
        })
        self.assertEqual(rc, 0, errors)
        self.assertIn("1 documentation-evidence", output)
        self.assertIn("0 coverage holes", output)

    def test_unbuilt_source_outside_documentation_is_a_hole(self):
        rc, output, errors = self.census({
            "src/orphan.ml": ("excluded", "not-built"),
        })
        self.assertEqual(rc, 1)
        self.assertIn("1 coverage holes", output)
        self.assertIn("unbuilt tracked source outside documentation: src/orphan.ml", errors)

    def test_built_documentation_is_decided_not_evidence(self):
        rc, output, errors = self.census({
            "docs/examples/example.ml": ("decided", ""),
            "docs/issues/history/acceptance/frozen.ml": ("excluded", "not-built"),
        }, {"docs/examples/dune": "(library (name example))\n"})
        self.assertEqual(rc, 0, errors)
        self.assertIn("1 decided", output)
        self.assertIn("1 documentation-evidence", output)


if __name__ == "__main__":
    unittest.main()
