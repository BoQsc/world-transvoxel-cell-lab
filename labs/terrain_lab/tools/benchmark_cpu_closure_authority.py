#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path


EXPECTED = {
    "workload_hash": "b758a78f2da5582081a579ea74de5bec0d33901a334001a395f3a462dbf27d44",
    "lod_streaming_hash": "4d3cbadcef8d851df1061e6845444ba9ad4c02ac9671b072c92b1b944a4e2314",
    "snapshot_query_hash": "2b3da9885262e7548e95192e698eb00eebe57fadc82e05aa05b5da83dbc2c689",
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Retain pinned world-transvoxel CPU closure authority."
    )
    parser.add_argument("--upstream-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--workload-runs", type=int, default=25)
    parser.add_argument("--workload-warmup", type=int, default=3)
    parser.add_argument("--soak-seconds", type=int, default=60)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tokens(line: str) -> dict[str, int | float | str]:
    result: dict[str, int | float | str] = {}
    for token in line.split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        try:
            result[key] = int(value)
            continue
        except ValueError:
            pass
        try:
            result[key] = float(value)
            continue
        except ValueError:
            result[key] = value
    return result


def marker(output: str, prefix: str) -> str:
    match = re.search(rf"^{re.escape(prefix)} (.+)$", output, re.MULTILINE)
    if match is None:
        raise RuntimeError(f"missing native marker: {prefix}\n{output}")
    return match.group(1).strip()


def main() -> int:
    args = parse_arguments()
    if args.workload_runs < 15 or args.workload_warmup < 1:
        raise RuntimeError("at least 15 measured workload runs and one warmup are required")
    if args.soak_seconds < 30:
        raise RuntimeError("the retained native closure soak must run for at least 30 seconds")
    upstream = args.upstream_root.resolve()
    sys.path.insert(0, str(upstream / "tools"))
    from wt_benchmark_common import percentile, run_process_with_peak

    commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=upstream, text=True
    ).strip()
    describe = subprocess.check_output(
        ["git", "describe", "--always", "--dirty"], cwd=upstream, text=True
    ).strip()
    executable_root = upstream / "build" / "native-tests"
    paths = {
        "workload_debug": executable_root
        / "test_wt_m5_workload.template_debug.x86_64.exe",
        "workload_release": executable_root
        / "test_wt_m5_workload.template_release.x86_64.exe",
        "lod_streaming_debug": executable_root
        / "test_wt_production_lod_streaming.template_debug.x86_64.exe",
        "lod_streaming_release": executable_root
        / "test_wt_production_lod_streaming.template_release.x86_64.exe",
        "snapshot_query_release": executable_root
        / "test_wt_production_snapshot_query.template_release.x86_64.exe",
        "soak_release": executable_root
        / "test_wt_m5_soak.template_release.x86_64.exe",
    }
    for name, path in paths.items():
        if not path.is_file():
            raise RuntimeError(f"missing {name} executable: {path}")

    def run(name: str, arguments: list[str] | None = None) -> dict:
        command = [paths[name], *(arguments or [])]
        started = time.perf_counter_ns()
        code, output, peak = run_process_with_peak(command, upstream)
        elapsed = time.perf_counter_ns() - started
        if code != 0:
            raise RuntimeError(f"{name} failed with {code}:\n{output}")
        if peak is None or peak <= 0:
            raise RuntimeError(f"{name} peak working set is unavailable")
        return {
            "status": "PASS",
            "duration_ns": elapsed,
            "peak_working_set_bytes": peak,
            "output": output,
        }

    build_matrix: dict[str, dict] = {}
    for configuration in ("debug", "release"):
        workload = run(f"workload_{configuration}")
        workload_hash = marker(workload["output"], "M5_WORKLOAD_HASH")
        workload_metrics = tokens(marker(workload["output"], "M5_WORKLOAD_METRICS"))
        if workload_hash != EXPECTED["workload_hash"]:
            raise RuntimeError(f"{configuration} workload hash changed: {workload_hash}")
        lod = run(f"lod_streaming_{configuration}")
        lod_hash = marker(lod["output"], "PRODUCTION_LOD_STREAMING_HASH")
        lod_metrics = tokens(marker(lod["output"], "PRODUCTION_LOD_STREAMING_EVIDENCE"))
        lod_pass = tokens(marker(lod["output"], "PRODUCTION_LOD_STREAMING_PASS"))
        if lod_hash != EXPECTED["lod_streaming_hash"]:
            raise RuntimeError(f"{configuration} LOD streaming hash changed: {lod_hash}")
        build_matrix[f"template_{configuration}"] = {
            "status": "PASS",
            "workload_hash": workload_hash,
            "workload_metrics": workload_metrics,
            "lod_streaming_hash": lod_hash,
            "lod_streaming_metrics": lod_metrics,
            "lod_streaming_contract": lod_pass,
            "peak_working_set_bytes": max(
                workload["peak_working_set_bytes"], lod["peak_working_set_bytes"]
            ),
        }

    benchmark = run(
        "workload_release",
        [
            "--benchmark-runs",
            str(args.workload_runs),
            "--warmup-runs",
            str(args.workload_warmup),
        ],
    )
    samples = [
        int(match.group(1))
        for match in re.finditer(
            r"^M5_WORKLOAD_BENCHMARK_SAMPLE run=\d+ duration_ns=(\d+)$",
            benchmark["output"],
            re.MULTILINE,
        )
    ]
    if len(samples) != args.workload_runs:
        raise RuntimeError("native workload benchmark sample count changed")

    query = run("snapshot_query_release")
    query_hash = marker(query["output"], "PRODUCTION_SNAPSHOT_QUERY_HASH")
    query_pass = tokens(marker(query["output"], "PRODUCTION_SNAPSHOT_QUERY_PASS"))
    if query_hash != EXPECTED["snapshot_query_hash"]:
        raise RuntimeError(f"snapshot query hash changed: {query_hash}")

    with tempfile.TemporaryDirectory(prefix="wt_tqp49_") as temporary:
        trace = Path(temporary) / "native_soak.wttrace"
        soak = run(
            "soak_release",
            [
                "--duration-ms",
                str(args.soak_seconds * 1000),
                "--sample-period-frames",
                "1024",
                "--trace",
                str(trace),
            ],
        )
        soak_metrics = tokens(marker(soak["output"], "M5_SOAK_METRICS"))
        soak_trace_hash = marker(soak["output"], "M5_SOAK_TRACE_SHA256")
        if not trace.is_file() or sha256(trace) != soak_trace_hash:
            raise RuntimeError("native soak trace hash mismatch")
        soak_trace_bytes = trace.stat().st_size

    report = {
        "schema": "world_transvoxel.terrain_lab.cpu_closure_native_authority.v1",
        "status": "PASS",
        "authority": {
            "repository": "world-transvoxel",
            "git_commit": commit,
            "git_describe": describe,
            "executables": {
                name: {
                    "path": path.relative_to(upstream).as_posix(),
                    "sha256": sha256(path),
                }
                for name, path in paths.items()
            },
        },
        "expected_contract_hashes": EXPECTED,
        "build_matrix": build_matrix,
        "representative_workload_distribution_ns": {
            "samples": len(samples),
            "p50": percentile(samples, 0.50),
            "p95": percentile(samples, 0.95),
            "p99": percentile(samples, 0.99),
            "worst": max(samples),
            "values": samples,
            "peak_working_set_bytes": benchmark["peak_working_set_bytes"],
        },
        "snapshot_query": {
            "status": "PASS",
            "hash": query_hash,
            "contract": query_pass,
            "duration_ns": query["duration_ns"],
            "peak_working_set_bytes": query["peak_working_set_bytes"],
        },
        "native_soak": {
            "status": "PASS",
            "requested_duration_seconds": args.soak_seconds,
            "metrics": soak_metrics,
            "trace_sha256": soak_trace_hash,
            "trace_bytes": soak_trace_bytes,
            "peak_working_set_bytes": soak["peak_working_set_bytes"],
        },
        "proof_map": {
            "TQP-45": [
                "interactive_edit_priority",
                "priority_ordered_loading_retry",
                "generation_cancellation_and_stale_discard",
                "bounded_readiness_latency",
            ],
            "TQP-46": [
                "visual_and_collision_demand_independence",
                "collision_reactivation_hysteresis",
                "replacement_collision_continuity",
                "collision_publication_priority_and_coalescing",
                "authoritative_sparse_query_without_render_residency",
            ],
            "TQP-47": [
                "bounded_native_worker_and_queue_workload",
                "debug_release_contract_identity",
                "peak_working_set_measurement",
            ],
            "TQP-49": [
                "fixed_duration_native_churn",
                "cancellations_and_stale_results",
                "bounded_readiness_and_queues",
                "binary_trace_integrity",
            ],
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "WT_TERRAIN_LAB_CPU_CLOSURE_NATIVE_PASS "
        f"commit={commit} runs={len(samples)} soak={args.soak_seconds}s"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
