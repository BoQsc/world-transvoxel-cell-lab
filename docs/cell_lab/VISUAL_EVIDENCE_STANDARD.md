# Cell Lab Visual Evidence Standard

Cell Lab screenshots are visual-regression references. They can expose drift,
cropping, missing geometry, diagnostic-color changes, and suspicious regions.
They are not standalone proof that Transvoxel geometry is correct.

Numeric and structural acceptance remains owned by the native-buffer,
topology, seam, feature-probe, edit-replay, determinism, collision, and
performance validators. A screenshot may support those results but cannot
replace them.

## Promotion Contract

A visual reference may be promoted only after:

1. A fresh graphical capture completes without script or renderer errors.
2. Geometry and labels are fully framed unless the view is explicitly a
   close-up or cutaway.
3. Captions and legends describe the rendered data accurately.
4. Diagnostic colors have an explicit meaning.
5. The image is inspected at its native resolution, not only in a contact
   sheet.
6. The complete numeric suite passes with unchanged locked results, unless a
   separately proven correction intentionally changes them.
7. `visual_manifest.json` records `HUMAN_REVIEWED` only after those checks.

## Machine Contract

The standards runner checks that every reviewed reference:

- has a declared view identity;
- exists at its locked dimensions and SHA-256;
- contains a minimum amount of content;
- belongs to the
  `visual_regression_not_standalone_correctness` evidence scope.

Fresh captures are compared with the committed references using renderer
variance thresholds. A passing pixel comparison means the presentation
reproduced the reviewed baseline. It does not promote that baseline into a
geometry invariant.

The committed visual contract is Windows, Forward+, D3D12, at 1152 by 648.
Captures from another renderer are useful for investigation but cannot replace
this baseline. Promotion also requires two repeat captures to agree before a
fresh third capture is accepted against the committed references.

## Density Slices

Density-region colors are sampled presentation cells:

- blue: the bilinear center estimate from four sampled corners is solid
  (`density < 0`);
- red: the bilinear center estimate is air (`density >= 0`);
- yellow: the linearly interpolated corner-sample `density = 0` contour;
- crosses: a subset of authoritative scalar-field samples.

The standard slice remains 32 by 32 cells with 33 by 33 samples. Its rendered
contour is diagnostic presentation derived from those locked samples.

## Failure Interpretation

A visual difference is an investigation trigger. Classify it before changing
any baseline:

- expected presentation change;
- capture or framing defect;
- renderer variance;
- lab visualization defect;
- native geometry or buffer defect.

Only the last category is grounds for an upstream correction, and it still
requires a minimized repro and independent numeric evidence.
