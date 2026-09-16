#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "azure-devops>=7.1.0b4",
#   "azure-identity>=1.15.0",
#   "msrest>=0.7.1",
#   "PyGithub>=2.1.1",
# ]
# ///
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
"""Offline regression tests for the personal PR/build watcher."""

from __future__ import annotations

import argparse
import io
import json
import os
import unittest
from contextlib import redirect_stderr
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import Mock, patch

from azure.devops.v7_1.build.models import Build, BuildRepository

import pr_ci_monitor_cli as monitor


class ReaderTests(unittest.TestCase):
    def test_github_reader_includes_base_identity(self):
        for base in (SimpleNamespace(ref="main", sha="base"), None):
            with (
                self.subTest(base=base),
                patch.dict(os.environ, {"GH_TOKEN": "unit-test-token"}),
                patch.object(monitor, "Github") as github,
            ):
                github.return_value.get_repo.return_value.get_pull.return_value = (
                    SimpleNamespace(
                        state="open",
                        head=SimpleNamespace(sha="head"),
                        base=base,
                        merge_commit_sha="merge",
                    )
                )
                reader = monitor.GithubPullReader()
                try:
                    result = reader.read(1)
                finally:
                    reader.close()
                self.assertEqual(result["baseRef"], base.ref if base else None)
                self.assertEqual(result["baseSha"], base.sha if base else None)

    def test_build_reader_includes_repository_identity(self):
        for repository in (
            BuildRepository(id="repo-id", name=monitor.REPOSITORY, type="GitHub"),
            None,
        ):
            with (
                self.subTest(repository=repository),
                patch.object(monitor.AzureBuildReader, "_client") as client,
            ):
                client.return_value.get_build.return_value = Build(
                    id=2, repository=repository
                )
                result = monitor.AzureBuildReader().read(2)
                self.assertEqual(
                    result["repository"],
                    {
                        "id": repository.id if repository else None,
                        "name": repository.name if repository else None,
                        "type": repository.type if repository else None,
                    },
                )
                json.dumps(result)


class ObservationTests(unittest.TestCase):
    def setUp(self):
        self.args = argparse.Namespace(
            pr_number=1,
            build_id=2,
            head_sha="head",
            base_ref="main",
            base_sha="base",
            merge_sha="merge",
            deadline=datetime(2030, 1, 1, tzinfo=timezone.utc),
        )
        self.pr = {
            "state": "OPEN",
            "headSha": "head",
            "baseRef": "main",
            "baseSha": "base",
            "mergeSha": "merge",
        }
        self.build = {
            "definition": {"name": monitor.PIPELINE},
            "repository": {"name": monitor.REPOSITORY, "type": "GitHub"},
            "sourceBranch": "refs/pull/1/merge",
            "sourceVersion": "merge",
            "status": "inProgress",
        }
        self.github_reader = Mock(spec=monitor.GithubPullReader)
        self.github_reader.read.return_value = self.pr
        self.build_reader = Mock(spec=monitor.AzureBuildReader)
        self.build_reader.read.return_value = self.build

    def observe(self):
        return monitor.observe(self.args, self.github_reader, self.build_reader)

    def test_matching_revision_and_repository_continue(self):
        observation, code = self.observe()
        self.assertIsNone(code)
        self.assertEqual(observation["outcome"], "running")
        self.assertEqual(observation["expected"]["baseRef"], "main")
        self.assertEqual(observation["expected"]["baseSha"], "base")
        self.assertEqual(observation["pr"], self.pr)
        json.dumps(observation)

    def test_base_drift_stops_even_when_head_and_merge_are_unchanged(self):
        for changes in (
            {"baseRef": "release/test"},
            {"baseSha": "new-base"},
            {"baseRef": None},
            {"baseSha": None},
        ):
            with self.subTest(changes=changes):
                self.github_reader.read.return_value = self.pr | changes
                observation, code = self.observe()
                self.assertEqual(code, monitor.EXIT_STOPPED)
                self.assertEqual(observation["outcome"], "revision_changed")
                self.build_reader.read.assert_not_called()

    def test_other_pr_changes_still_stop(self):
        for changes in (
            {"state": "CLOSED"},
            {"headSha": "new-head"},
            {"mergeSha": "new-merge"},
        ):
            with self.subTest(changes=changes):
                self.github_reader.read.return_value = self.pr | changes
                _, code = self.observe()
                self.assertEqual(code, monitor.EXIT_STOPPED)
                self.build_reader.read.assert_not_called()

    def test_wrong_or_missing_repository_is_rejected(self):
        for repository in (
            None,
            {},
            {"name": "microsoft/another-repo", "type": "GitHub"},
            {"name": monitor.REPOSITORY, "type": "TfsGit"},
            {"name": monitor.REPOSITORY},
            {"name": None, "type": "GitHub"},
        ):
            with self.subTest(repository=repository):
                self.build_reader.read.return_value = self.build | {
                    "repository": repository
                }
                observation, code = self.observe()
                self.assertEqual(code, monitor.EXIT_ASSOCIATION_ERROR)
                self.assertEqual(observation["outcome"], "association_changed")
                self.assertEqual(observation["reason"]["repository"], repository)

    def test_github_repository_names_are_case_insensitive(self):
        self.build["repository"]["name"] = monitor.REPOSITORY.upper()
        _, code = self.observe()
        self.assertIsNone(code)

    def test_other_build_association_changes_are_rejected(self):
        for changes in (
            {"definition": {"name": "core-ci-manual"}},
            {"sourceBranch": "refs/pull/3/merge"},
            {"sourceVersion": "another-merge"},
        ):
            with self.subTest(changes=changes):
                self.build_reader.read.return_value = self.build | changes
                _, code = self.observe()
                self.assertEqual(code, monitor.EXIT_ASSOCIATION_ERROR)

    def test_build_outcomes_are_preserved(self):
        for status, result, outcome, expected_code in (
            ("notStarted", None, "running", None),
            ("postponed", None, "running", None),
            ("cancelling", None, "cancelling", monitor.EXIT_STOPPED),
            ("completed", "succeeded", "succeeded", 0),
            ("completed", "failed", "failed", monitor.EXIT_FAILED),
            (
                "completed", "partiallySucceeded", "partially_succeeded",
                monitor.EXIT_PARTIALLY_SUCCEEDED,
            ),
            ("completed", "canceled", "canceled", monitor.EXIT_STOPPED),
            ("completed", "unexpected", "unknown_result", monitor.EXIT_UNKNOWN_RESULT),
            ("unexpected", None, "unknown_status", monitor.EXIT_UNKNOWN_RESULT),
        ):
            with self.subTest(status=status, result=result):
                self.build_reader.read.return_value = self.build | {
                    "status": status,
                    "result": result,
                }
                observation, code = self.observe()
                self.assertEqual(code, expected_code)
                self.assertEqual(observation["outcome"], outcome)


class ParserTests(unittest.TestCase):
    def test_base_arguments_are_required_and_preserved(self):
        options = {
            "--pr-number": "1",
            "--build-id": "2",
            "--head-sha": "head",
            "--base-ref": "main",
            "--base-sha": "base",
            "--merge-sha": "merge",
        }
        for omitted in ("--base-ref", "--base-sha", None):
            with self.subTest(omitted=omitted):
                argv = ["watch", "--once"]
                for name, value in options.items():
                    if name != omitted:
                        argv.extend((name, value))
                parser = monitor.build_parser()
                if omitted is not None:
                    with (
                        redirect_stderr(io.StringIO()),
                        self.assertRaises(SystemExit) as error,
                    ):
                        parser.parse_args(argv)
                    self.assertEqual(error.exception.code, 2)
                else:
                    args = parser.parse_args(argv)
                    self.assertEqual(args.base_ref, "main")
                    self.assertEqual(args.base_sha, "base")


if __name__ == "__main__":
    unittest.main()
