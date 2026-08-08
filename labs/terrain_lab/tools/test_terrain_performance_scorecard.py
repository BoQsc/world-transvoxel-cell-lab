#!/usr/bin/env python3
"""Focused tests for terrain-performance comparison accounting."""

from __future__ import annotations

import unittest

from measure_low_power_profiles import summarize_process_telemetry
from terrain_performance_scorecard import build_scorecard


class TerrainPerformanceScorecardTests(unittest.TestCase):
    def test_scorecard_exposes_comparable_terrain_work(self) -> None:
        report = {
            "schema": "qualification.v2",
            "status": "DEV_OBSERVATION_ONLY",
            "run_mode": "development_observation",
            "profile_id": "low_power_16w_60fps",
            "workload": {
                "measurement": {
                    "elapsed_seconds": 10.0,
                    "frame_count": 600,
                    "frame": {"p95_usec": 17000, "p99_usec": 19000},
                    "process": {"p95_usec": 4000},
                    "physics": {},
                    "render_cpu": {},
                    "render_gpu": {},
                    "metric_deltas": {
                        "application_applied_render": 100,
                        "application_applied_collision": 50,
                        "published_events": 200,
                        "edit_commits": 2,
                    },
                    "action_counts": {"dig_commits": 1, "construction_commits": 1},
                    "memory": {"peak_bytes": 1024},
                    "queue_peaks": {"scheduler": 2},
                }
            },
            "process_telemetry": {
                "available": True,
                "average_active_core_equivalents": 1.5,
                "amortized_process_cpu_time_per_render_publication_ms": 150.0,
            },
            "auxiliary_power_observations": {
                "cpu_package": {
                    "available": False,
                    "reason": "sensor absent",
                    "watts": None,
                }
            },
        }

        scorecard = build_scorecard(report)

        self.assertTrue(scorecard["qualification"]["comparison_only"])
        self.assertEqual(
            scorecard["terrain_work"]["render_publications_per_second"], 10.0
        )
        self.assertEqual(
            scorecard["terrain_work"]["collision_publications_per_second"], 5.0
        )
        self.assertEqual(
            scorecard["cpu"]["process_wide"]["average_active_core_equivalents"],
            1.5,
        )
        self.assertIn("sensor absent", scorecard["limitations"])
        edit_metric = next(
            item
            for item in scorecard["comparison_metrics"]
            if item["id"] == "edit_visual_response_p99"
        )
        self.assertIsNone(edit_metric["value"])

    def test_process_summary_includes_worker_thread_cpu_time(self) -> None:
        samples = [
            {
                "timestamp_unix_seconds": 10.0,
                "process": {
                    "available": True,
                    "logical_cpu_count": 4,
                    "cpu_total_seconds": 1.0,
                    "cpu_percent_one_core_scale": 0.0,
                    "resident_memory_bytes": 100,
                    "thread_count": 3,
                },
            },
            {
                "timestamp_unix_seconds": 12.0,
                "process": {
                    "available": True,
                    "logical_cpu_count": 4,
                    "cpu_total_seconds": 3.0,
                    "cpu_percent_one_core_scale": 100.0,
                    "resident_memory_bytes": 200,
                    "thread_count": 4,
                },
            },
        ]

        summary = summarize_process_telemetry(samples, 2.0, 120, 20, 10, 2)

        self.assertTrue(summary["available"])
        self.assertTrue(summary["worker_threads_included"])
        self.assertEqual(summary["process_cpu_seconds"], 2.0)
        self.assertEqual(summary["average_active_core_equivalents"], 1.0)
        self.assertEqual(summary["average_machine_cpu_capacity_percent"], 25.0)
        self.assertEqual(
            summary["amortized_process_cpu_time_per_render_publication_ms"], 100.0
        )


if __name__ == "__main__":
    unittest.main()
