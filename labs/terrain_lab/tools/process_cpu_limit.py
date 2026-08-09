#!/usr/bin/env python3
"""Fail-closed process CPU-affinity guard for terrain lab workloads."""

from __future__ import annotations

from collections.abc import Sequence

import psutil


MAX_LOGICAL_CPU_COUNT = 3


def enforce_current_process_limit(requested: int = MAX_LOGICAL_CPU_COUNT) -> list[int]:
	if requested < 1 or requested > MAX_LOGICAL_CPU_COUNT:
		raise ValueError(
			f"logical CPU limit must be between 1 and {MAX_LOGICAL_CPU_COUNT}, got {requested}"
		)
	process = psutil.Process()
	available = process.cpu_affinity()
	if len(available) < requested:
		raise RuntimeError(
			f"requested {requested} logical CPUs but affinity exposes only {available}"
		)
	selected = available[:requested]
	process.cpu_affinity(selected)
	actual = process.cpu_affinity()
	if actual != selected:
		raise RuntimeError(f"failed to enforce CPU affinity: requested={selected} actual={actual}")
	return actual


def verify_process_limit(pid: int, expected: Sequence[int]) -> list[int]:
	actual = psutil.Process(pid).cpu_affinity()
	expected_list = list(expected)
	if actual != expected_list:
		raise RuntimeError(
			f"child process escaped CPU affinity: expected={expected_list} actual={actual}"
		)
	if len(actual) > MAX_LOGICAL_CPU_COUNT:
		raise RuntimeError(f"child process uses more than {MAX_LOGICAL_CPU_COUNT} logical CPUs")
	return actual
