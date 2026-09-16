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
"""Read-only bounded watcher for the personal `pr-ci-monitor` Copilot skill.

The helper observes one already-associated microsoft/meru-core PR core-ci build
through the GitHub and Azure DevOps SDKs. It does not discover builds, diagnose
failures, trigger builds, post comments, persist state, or own retry policy.
Each observation is emitted as one JSON object on stdout.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from typing import Any, NoReturn

from azure.core.exceptions import ClientAuthenticationError
from azure.devops.connection import Connection
from azure.devops.exceptions import AzureDevOpsServiceError
from azure.identity import AzureCliCredential, CredentialUnavailableError
from github import Auth, Github, GithubException
from msrest.authentication import BasicTokenAuthentication
from msrest.exceptions import ClientRequestError


REPOSITORY = "microsoft/meru-core"
PIPELINE = "core-ci"
DEFAULT_ORG = os.environ.get("ADO_ORG_URL", "https://dev.azure.com/project-meru")
DEFAULT_PROJECT = os.environ.get("ADO_PROJECT", "eng")
MIN_POLL_SECONDS = 60
DEFAULT_POLL_SECONDS = 120
DEFAULT_TIMEOUT = timedelta(hours=2)
ADO_SCOPE = "499b84ac-1321-427f-aa17-267ca6975798/.default"

EXIT_FAILED = 10
EXIT_PARTIALLY_SUCCEEDED = 11
EXIT_STOPPED = 12
EXIT_DEADLINE = 13
EXIT_UNKNOWN_RESULT = 14
EXIT_GITHUB_ERROR = 20
EXIT_ADO_ERROR = 21
EXIT_ASSOCIATION_ERROR = 22


def die(message: str, code: int = 1) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def utc_timestamp(value: datetime | None = None) -> str:
    current = value or datetime.now(timezone.utc)
    return current.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_deadline(value: str) -> datetime:
    try:
        deadline = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "deadline must be an ISO8601 timestamp, for example "
            "2026-09-09T19:07:00Z"
        ) from error

    if deadline.tzinfo is None or deadline.utcoffset() is None:
        raise argparse.ArgumentTypeError("deadline must include a timezone")
    return deadline.astimezone(timezone.utc)


class GithubPullReader:
    """Read the current state and head/base/merge revisions for one GitHub PR."""

    def __init__(self) -> None:
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        if not token:
            die(
                "GitHub SDK authentication requires GH_TOKEN or GITHUB_TOKEN. "
                "The watcher does not fall back to the GitHub CLI.",
                EXIT_GITHUB_ERROR,
            )
        self._github = Github(auth=Auth.Token(token), timeout=60, retry=2)
        try:
            self._repository = self._github.get_repo(REPOSITORY)
        except GithubException as error:
            die(
                f"Failed to open GitHub repository {REPOSITORY}: {error}",
                EXIT_GITHUB_ERROR,
            )

    def close(self) -> None:
        self._github.close()

    def read(self, pr_number: int) -> dict[str, Any]:
        try:
            pull = self._repository.get_pull(pr_number)
            state = pull.state.upper()
            head_sha = pull.head.sha if pull.head else None
            base_ref = pull.base.ref if pull.base else None
            base_sha = pull.base.sha if pull.base else None
            merge_sha = pull.merge_commit_sha
        except GithubException as error:
            die(
                f"Failed to read {REPOSITORY} PR #{pr_number}: {error}",
                EXIT_GITHUB_ERROR,
            )

        return {
            "state": state,
            "headSha": head_sha,
            "baseRef": base_ref,
            "baseSha": base_sha,
            "mergeSha": merge_sha,
        }


class AzureBuildReader:
    """Read normalized build metadata with a refreshable Azure CLI credential."""

    def __init__(self) -> None:
        self._credential = AzureCliCredential()
        self._build_client: Any = None
        self._token_expires_on = 0

    def _client(self) -> Any:
        token_is_fresh = time.time() < self._token_expires_on - 300
        if self._build_client is not None and token_is_fresh:
            return self._build_client

        try:
            access_token = self._credential.get_token(ADO_SCOPE)
        except (CredentialUnavailableError, ClientAuthenticationError) as error:
            die(
                f"Failed to authenticate to Azure DevOps: {error}. Run `az login` "
                "with an account that can access the project.",
                EXIT_ADO_ERROR,
            )

        credentials = BasicTokenAuthentication({"access_token": access_token.token})
        connection = Connection(base_url=DEFAULT_ORG, creds=credentials)
        self._build_client = connection.clients.get_build_client()
        self._token_expires_on = access_token.expires_on
        return self._build_client

    def read(self, build_id: int) -> dict[str, Any]:
        try:
            build = self._client().get_build(
                project=DEFAULT_PROJECT,
                build_id=build_id,
            )
        except (AzureDevOpsServiceError, ClientRequestError) as error:
            die(
                f"Failed to read Azure DevOps build {build_id}: {error}",
                EXIT_ADO_ERROR,
            )

        return {
            "id": build.id,
            "buildNumber": build.build_number,
            "status": build.status,
            "result": build.result,
            "sourceBranch": build.source_branch,
            "sourceVersion": build.source_version,
            "reason": build.reason,
            "queueTime": str(build.queue_time) if build.queue_time else None,
            "startTime": str(build.start_time) if build.start_time else None,
            "finishTime": str(build.finish_time) if build.finish_time else None,
            "definition": {
                "id": build.definition.id if build.definition else None,
                "name": build.definition.name if build.definition else None,
            },
            "repository": {
                "id": build.repository.id if build.repository else None,
                "name": build.repository.name if build.repository else None,
                "type": build.repository.type if build.repository else None,
            },
            "url": (
                f"{DEFAULT_ORG.rstrip('/')}/{DEFAULT_PROJECT}/_build/results"
                f"?buildId={build.id}"
            ),
        }


def base_observation(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "event": "observation",
        "timestamp": utc_timestamp(),
        "repository": REPOSITORY,
        "prNumber": args.pr_number,
        "buildId": args.build_id,
        "deadline": utc_timestamp(args.deadline),
        "expected": {
            "headSha": args.head_sha,
            "baseRef": args.base_ref,
            "baseSha": args.base_sha,
            "mergeSha": args.merge_sha,
            "repository": REPOSITORY,
            "pipeline": PIPELINE,
            "sourceBranch": f"refs/pull/{args.pr_number}/merge",
        },
    }


def observe(
    args: argparse.Namespace,
    github_reader: GithubPullReader,
    build_reader: AzureBuildReader,
) -> tuple[dict[str, Any], int | None]:
    observation = base_observation(args)
    pr = github_reader.read(args.pr_number)
    state = pr.get("state")
    head_sha = pr.get("headSha")
    base_ref = pr.get("baseRef")
    base_sha = pr.get("baseSha")
    merge_sha = pr.get("mergeSha")
    observation["pr"] = {
        "state": state,
        "headSha": head_sha,
        "baseRef": base_ref,
        "baseSha": base_sha,
        "mergeSha": merge_sha,
    }

    if state != "OPEN":
        observation["outcome"] = "pr_not_open"
        observation["reason"] = f"PR state is {state!r}"
        return observation, EXIT_STOPPED

    if head_sha != args.head_sha:
        observation["outcome"] = "revision_changed"
        observation["reason"] = f"PR head changed from {args.head_sha} to {head_sha}"
        return observation, EXIT_STOPPED

    if base_ref != args.base_ref or base_sha != args.base_sha:
        observation["outcome"] = "revision_changed"
        observation["reason"] = (
            f"PR base changed from {args.base_ref}@{args.base_sha} "
            f"to {base_ref}@{base_sha}"
        )
        return observation, EXIT_STOPPED

    if merge_sha != args.merge_sha:
        observation["outcome"] = "revision_changed"
        observation["reason"] = (
            f"PR merge changed from {args.merge_sha} to {merge_sha}"
        )
        return observation, EXIT_STOPPED

    build = build_reader.read(args.build_id)
    observation["build"] = build

    definition = build.get("definition")
    pipeline = definition.get("name") if isinstance(definition, dict) else None
    repository = build.get("repository")
    repository_name = repository.get("name") if isinstance(repository, dict) else None
    repository_type = repository.get("type") if isinstance(repository, dict) else None
    source_branch = build.get("sourceBranch")
    source_version = build.get("sourceVersion")
    expected_branch = f"refs/pull/{args.pr_number}/merge"
    if (
        not isinstance(repository_name, str)
        or repository_name.casefold() != REPOSITORY.casefold()
        or repository_type != "GitHub"
        or pipeline != PIPELINE
        or source_branch != expected_branch
        or source_version != args.merge_sha
    ):
        observation["outcome"] = "association_changed"
        observation["reason"] = {
            "repository": repository,
            "pipeline": pipeline,
            "sourceBranch": source_branch,
            "sourceVersion": source_version,
        }
        return observation, EXIT_ASSOCIATION_ERROR

    status = build.get("status")
    result = build.get("result")
    if status in {"notStarted", "inProgress", "postponed"}:
        observation["outcome"] = "running"
        return observation, None

    if status == "cancelling":
        observation["outcome"] = "cancelling"
        return observation, EXIT_STOPPED

    if status != "completed":
        observation["outcome"] = "unknown_status"
        observation["reason"] = f"Unexpected build status {status!r}"
        return observation, EXIT_UNKNOWN_RESULT

    outcomes = {
        "succeeded": ("succeeded", 0),
        "failed": ("failed", EXIT_FAILED),
        "partiallySucceeded": ("partially_succeeded", EXIT_PARTIALLY_SUCCEEDED),
        "canceled": ("canceled", EXIT_STOPPED),
    }
    outcome = outcomes.get(result)
    if outcome is None:
        observation["outcome"] = "unknown_result"
        observation["reason"] = f"Unexpected completed-build result {result!r}"
        return observation, EXIT_UNKNOWN_RESULT

    observation["outcome"], exit_code = outcome
    return observation, exit_code


def emit(value: dict[str, Any]) -> None:
    print(json.dumps(value, sort_keys=True), flush=True)


def deadline_event(args: argparse.Namespace) -> dict[str, Any]:
    event = base_observation(args)
    event["event"] = "deadline"
    event["outcome"] = "deadline_reached"
    event["deadline"] = utc_timestamp(args.deadline)
    return event


def cmd_watch(args: argparse.Namespace) -> int:
    if not args.once and args.poll_seconds < MIN_POLL_SECONDS:
        die(
            f"--poll-seconds must be at least {MIN_POLL_SECONDS} for ongoing monitoring.",
            2,
        )

    started_at = datetime.now(timezone.utc)
    if args.deadline is None:
        args.deadline = started_at + DEFAULT_TIMEOUT

    if started_at >= args.deadline:
        emit(deadline_event(args))
        return EXIT_DEADLINE

    github_reader = GithubPullReader()
    build_reader = AzureBuildReader()
    try:
        while True:
            if datetime.now(timezone.utc) >= args.deadline:
                emit(deadline_event(args))
                return EXIT_DEADLINE

            observation, exit_code = observe(args, github_reader, build_reader)
            emit(observation)
            if exit_code is not None:
                return exit_code
            if args.once:
                return 0

            remaining_seconds = (
                args.deadline - datetime.now(timezone.utc)
            ).total_seconds()
            if remaining_seconds <= 0:
                continue
            time.sleep(min(args.poll_seconds, remaining_seconds))
    finally:
        github_reader.close()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pr_ci_monitor_cli.py",
        description=(
            "Read one already-associated microsoft/meru-core PR core-ci build "
            "through native SDKs until it completes or its association changes."
        ),
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    watch = subparsers.add_parser(
        "watch",
        help="Watch one core-ci build until completion, revision drift, or deadline.",
    )
    watch.add_argument("--pr-number", type=int, required=True)
    watch.add_argument("--build-id", type=int, required=True)
    watch.add_argument("--head-sha", required=True)
    watch.add_argument(
        "--base-ref", required=True, help="Expected PR target branch name, e.g. main."
    )
    watch.add_argument("--base-sha", required=True)
    watch.add_argument("--merge-sha", required=True)
    watch.add_argument(
        "--deadline",
        type=parse_deadline,
        help="Absolute ISO8601 deadline with timezone; default: two hours from start.",
    )
    watch.add_argument(
        "--poll-seconds",
        type=int,
        default=DEFAULT_POLL_SECONDS,
        help=(
            f"Polling cadence; default {DEFAULT_POLL_SECONDS}s, "
            f"minimum {MIN_POLL_SECONDS}s."
        ),
    )
    watch.add_argument(
        "--once",
        action="store_true",
        help="Make one observation and exit; useful for binding and validation.",
    )
    watch.set_defaults(func=cmd_watch)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
