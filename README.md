# ICD Final Project

This repository contains the RTL design history, final submission files, synthesis constraints, and project report for the ICD final project.

## Repository Layout

### `final_submission/`

Final hand-in files.

- `core.v`: final selected RTL implementation.
- `core_v_original.sdc`: final synthesis constraint file used for the selected result.
- `README.md`: short note about the final submission package.

The final RTL is based on `core_2line_bypass_fifo_pixpipe_lanepix_drain11.v`. The design uses a two-line circular buffer, input-row bypass FIFO, lane-pixel pipeline, output address counter, and digit-by-digit arithmetic cube-root activation.

### `core_versions/`

Archive of the major RTL versions explored during optimization.

- `00_final/`: final selected architecture, kept under its full experimental filename.
- `01_baseline_streaming/`: early baseline, streaming, and multi-cycle versions.
- `02_pipeline_experiments/`: streaming pipeline, deep pipeline, area cleanup, and cube-root datapath experiments.
- `03_convshare_digitcube/`: convolution-sharing and digit-cube-root variants.
- `04_2line_bypass/`: two-line buffer, bypass FIFO, pixel-pipeline, lane-pixel, and final two-line experiments.
- `05_mac_multicycle_rejected/`: MAC multi-cycle experiments that were rejected due to worse runtime and/or area.
- `docs/`: architecture notes and LaTeX design summary.

See `core_versions/README.md` for a more detailed version index.

### `constraints/`

Collected SDC files.

- `core_v_original.sdc`: final constraint file.
- `course_core_original.sdc`: original course synthesis constraint file.

### `1142_ICD_final (1)/`

Original course project package, including testbench, RTL run scripts, synthesis scripts, and gate-level simulation flow.

This folder is kept for reproducibility. Some local files inside this folder may have been modified during testing; check `git status` before committing if you want to include or discard those local edits.

### Root-Level Documents

- `1142_ICD_final.pdf`: original project specification.
- `ICD Final Project提醒.txt`: project reminders and notes.
- `b13901080_report.pdf`: final project report. It summarizes the implemented architecture, optimization process, and design results.

## Final Architecture Summary

The final design processes the image in a streaming manner. Instead of keeping three or four complete line buffers, it uses two full line buffers plus a small input-row FIFO:

- top row: read from one line buffer,
- middle row: read from the other line buffer,
- bottom row: generated from `prev2_grp`, `prev1_grp`, and current input data.

A lane-pixel pipeline organizes the required 3-by-3 pixels for four output lanes before the MAC stage. This removes stride-dependent muxing from the arithmetic stage and improves timing stability.

The activation computes:

```text
x^(2/3) = cube_root(x^2)
```

The cube root is implemented using a six-stage digit-by-digit arithmetic pipeline with digit trials `32, 16, 8, 4, 2, 1`. It is not implemented as a lookup table.
