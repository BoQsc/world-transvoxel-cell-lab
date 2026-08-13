# World Transvoxel Labs

Godot research and qualification monorepo for the `world-transvoxel` addon
stack.

This repository contains separate lab addons that share one pinned native
dependency and one Godot host project. Sharing a repository does not give one
lab ownership over another.

## Lab Boundaries

| Addon | Status | Responsibility |
| --- | --- | --- |
| `world_transvoxel_cell_lab` | Qualified milestones 1-29 | Native cells, transitions, chunks, seams, minimized repros, controlled terrain fixtures, and primitive benchmarks |
| `world_transvoxel_terrain_lab` | CPU-B2 causal attribution retained; CPU-B3 next; TQP-58 blocked | Controlled research into edit semantics, materials, resolution, adaptive terrain, large terrain, structural behavior, GPU candidates, and system performance |

The production addons and game remain separate repositories:

| Repository | Responsibility |
| --- | --- |
| `world-transvoxel` | Native meshing and low-level terrain primitives |
| `world-transvoxel-terrain` | Reusable game-facing terrain runtime |
| `world-transvoxel-integration-game` | Human-playable downstream production validation |

## Dependency Rules

```text
world_transvoxel_cell_lab
    -> world_transvoxel

world_transvoxel_terrain_lab
    -> world_transvoxel
    -> pinned world_transvoxel_terrain candidate for qualification only

world_transvoxel_cell_lab
    -X-> world_transvoxel_terrain_lab
```

`-X->` is a forbidden dependency. Neither lab addon is a production runtime
dependency. Experimental behavior is promoted into its owning production
repository only after qualification.

The monorepo does not vendor or install `world_transvoxel_terrain`. TQP-51 pins
the sibling candidate repository for cross-repository qualification only; the
Terrain Lab runtime continues to depend solely on the pinned native addon.

## Project Layout

```text
addons/
  world_transvoxel/                pinned native dependency
  world_transvoxel_cell_lab/       qualified Cell Lab addon
  world_transvoxel_terrain_lab/    separate Terrain Lab addon
docs/
  cell_lab/                        Cell Lab architecture and standards
  terrain_lab/                     Terrain Qualification Program
labs/
  cell_lab/
    scenes/                        rendered Cell Lab host scene
    captures/                      local Cell Lab visual output
    tools/                         Cell Lab validation and evidence tools
  terrain_lab/                     controlled Terrain Lab scene ownership
shared/
  tools/                           repository-wide infrastructure
```

The current main scene remains the rendered Cell Lab so the conversion does
not change its established inspection workflow.

## Documentation

- [Cell Lab overview](docs/cell_lab/README.md)
- [Cell Lab architecture](docs/cell_lab/ARCHITECTURE.md)
- [Cell Lab roadmap](docs/cell_lab/ROADMAP.md)
- [Cell Lab qualification standard](docs/cell_lab/QUALIFICATION_STANDARD.md)
- [Canonical reference terrain](docs/cell_lab/REFERENCE_TERRAIN_STANDARD.md)
- [Cell Lab visual evidence standard](docs/cell_lab/VISUAL_EVIDENCE_STANDARD.md)
- [Terrain Qualification Program](docs/terrain_lab/TERRAIN_QUALIFICATION_PROGRAM.md)

## Current Commands

Run the qualified Cell Lab suite:

```text
godot --headless --path . --script labs/cell_lab/tools/run_cell_lab_validation.gd -- all
```

Run the Cell Lab structural smoke:

```text
godot --headless --path . --script addons/world_transvoxel_cell_lab/tests/wt_cell_lab_smoke.gd
```

Run the Terrain Lab boundary smoke:

```text
godot --headless --path . --script addons/world_transvoxel_terrain_lab/tests/wt_terrain_lab_smoke.gd
```

Repository-local tags and commits should identify ownership with
`cell-lab`, `terrain-lab`, or `shared` scope. Changes to shared pinned
dependencies must run both lab suites.
