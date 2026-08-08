#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path


EXPECTED_HASH = "4cfe12662b60691f93eda8a27d20e1c978e9bab58c2c144b323750d2f39316bf"
EXPECTED_COUNTERS = {
    "orders": 64,
    "records": 8,
    "stale": 3,
    "cancellations": 1,
    "allocation_faults": 2,
    "interruption": 1,
    "malformed": 2,
    "shutdown": "drained",
    "first_divergence_generation": 4,
}
HASH_PATTERN = re.compile(r"^FAULT_ORDER_DETERMINISM_HASH ([0-9a-f]{64})$", re.MULTILINE)
PASS_PATTERN = re.compile(r"^FAULT_ORDER_DETERMINISM_PASS (.+)$", re.MULTILINE)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Retain repeated world-transvoxel fault-order authority runs."
    )
    parser.add_argument("--upstream-root", type=Path, required=True)
    parser.add_argument("--executable", type=Path)
    parser.add_argument("--release-executable", type=Path)
    parser.add_argument("--runs", type=int, default=15)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def parse_output(output: str) -> tuple[str, dict[str, int | str]]:
    hash_match = HASH_PATTERN.search(output)
    pass_match = PASS_PATTERN.search(output)
    if hash_match is None or pass_match is None:
        raise RuntimeError("fault-order executable did not emit its authority markers")
    counters: dict[str, int | str] = {}
    for token in pass_match.group(1).split():
        key, value = token.split("=", 1)
        counters[key] = int(value) if value.isdigit() else value
    return hash_match.group(1), counters


def main() -> int:
    args = parse_arguments()
    upstream_root = args.upstream_root.resolve()
    executable = args.executable
    if executable is None:
        executable = Path(
            "build/native-tests/test_wt_fault_order_determinism.template_debug.x86_64.exe"
        )
    if not executable.is_absolute():
        executable = upstream_root / executable
    executable = executable.resolve()
    release_executable = args.release_executable
    if release_executable is None:
        release_executable = Path(
            "build/native-tests/test_wt_fault_order_determinism.template_release.x86_64.exe"
        )
    if not release_executable.is_absolute():
        release_executable = upstream_root / release_executable
    release_executable = release_executable.resolve()
    if args.runs < 7 or args.warmup < 0:
        raise RuntimeError("at least seven measured runs and a non-negative warmup are required")
    if not executable.is_file():
        raise RuntimeError(f"fault-order executable is absent: {executable}")
    if not release_executable.is_file():
        raise RuntimeError(
            f"fault-order release executable is absent: {release_executable}"
        )

    upstream_tools = upstream_root / "tools"
    sys.path.insert(0, str(upstream_tools))
    from wt_benchmark_common import percentile, run_process_with_peak, sha256

    commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=upstream_root, text=True
    ).strip()
    runs: list[dict] = []
    for index in range(args.warmup + args.runs):
        started = time.perf_counter_ns()
        return_code, output, peak = run_process_with_peak([executable], upstream_root)
        duration_ns = time.perf_counter_ns() - started
        if return_code != 0:
            raise RuntimeError(f"fault-order run failed with {return_code}:\n{output}")
        native_hash, counters = parse_output(output)
        if native_hash != EXPECTED_HASH:
            raise RuntimeError(f"fault-order authority hash changed: {native_hash}")
        if counters != EXPECTED_COUNTERS:
            raise RuntimeError(f"fault-order counters changed: {counters}")
        if index >= args.warmup:
            if peak is None or peak <= 0:
                raise RuntimeError("Windows peak working set was unavailable")
            runs.append(
                {
                    "duration_ns": duration_ns,
                    "peak_working_set_bytes": peak,
                    "native_hash": native_hash,
                    "counters": counters,
                }
            )

    durations = [int(run["duration_ns"]) for run in runs]
    peaks = [int(run["peak_working_set_bytes"]) for run in runs]
    release_code, release_output, release_peak = run_process_with_peak(
        [release_executable], upstream_root
    )
    if release_code != 0:
        raise RuntimeError(
            f"fault-order release verification failed with {release_code}:\n"
            f"{release_output}"
        )
    release_hash, release_counters = parse_output(release_output)
    if release_hash != EXPECTED_HASH or release_counters != EXPECTED_COUNTERS:
        raise RuntimeError("fault-order release authority differs from debug")
    if release_peak is None or release_peak <= 0:
        raise RuntimeError("release Windows peak working set was unavailable")
    report = {
        "schema": "world_transvoxel.terrain_lab.fault_order_native_benchmark.v1",
        "status": "PASS",
        "authority": {
            "repository": "world-transvoxel",
            "git_commit": commit,
            "executable": executable.relative_to(upstream_root).as_posix(),
            "executable_sha256": sha256(executable),
            "release_executable": release_executable.relative_to(
                upstream_root
            ).as_posix(),
            "release_executable_sha256": sha256(release_executable),
            "native_contract_hash": EXPECTED_HASH,
        },
        "method": {
            "warmup_runs": args.warmup,
            "measured_runs": args.runs,
            "memory_metric": "windows_peak_working_set",
            "process_scope": "one_complete_native_fault_corpus_per_process",
        },
        "summary": {
            "fixed_counters": EXPECTED_COUNTERS,
            "duration_ns": {
                "samples": len(durations),
                "p50": percentile(durations, 0.50),
                "p95": percentile(durations, 0.95),
                "p99": percentile(durations, 0.99),
                "worst": max(durations),
            },
            "peak_working_set_bytes": {
                "samples": len(peaks),
                "p50": percentile(peaks, 0.50),
                "p95": percentile(peaks, 0.95),
                "p99": percentile(peaks, 0.99),
                "worst": max(peaks),
            },
        },
        "build_matrix": {
            "template_debug": {
                "status": "PASS",
                "native_hash": EXPECTED_HASH,
                "fixed_counters": EXPECTED_COUNTERS,
                "measured_runs": args.runs,
            },
            "template_release": {
                "status": "PASS",
                "native_hash": release_hash,
                "fixed_counters": release_counters,
                "verification_runs": 1,
                "peak_working_set_bytes": release_peak,
            },
        },
        "runs": runs,
        "claim": "REFERENCE_ONLY_NOT_A_PRODUCTION_PERFORMANCE_GATE",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "WT_TERRAIN_LAB_FAULT_ORDER_NATIVE_PASS "
        f"runs={args.runs} hash={EXPECTED_HASH}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
