#!/usr/bin/env python3
"""Run a command with the terrain lab's hard logical-CPU ceiling."""

from __future__ import annotations

import argparse
import subprocess
import sys

from process_cpu_limit import (
	MAX_LOGICAL_CPU_COUNT,
	enforce_current_process_limit,
	verify_process_limit,
)


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument(
		"--logical-cpus",
		type=int,
		default=MAX_LOGICAL_CPU_COUNT,
		help=f"logical CPUs to expose; hard maximum is {MAX_LOGICAL_CPU_COUNT}",
	)
	parser.add_argument("command", nargs=argparse.REMAINDER)
	args = parser.parse_args()
	command = args.command[1:] if args.command[:1] == ["--"] else args.command
	if not command:
		parser.error("a command is required after --")

	affinity = enforce_current_process_limit(args.logical_cpus)
	process = subprocess.Popen(command)
	try:
		child_affinity = verify_process_limit(process.pid, affinity)
	except Exception:
		process.terminate()
		process.wait(timeout=10)
		raise
	print(
		"WT_TERRAIN_CPU_LIMIT "
		f"logical_cpus={len(child_affinity)} affinity={child_affinity} pid={process.pid}",
		flush=True,
	)
	return process.wait()


if __name__ == "__main__":
	sys.exit(main())
