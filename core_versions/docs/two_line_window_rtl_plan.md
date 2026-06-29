# Two-Line Window RTL Attempt Plan

This note captures the concrete schedule needed for a 2-line-buffer, 4-output-per-cycle architecture.
The key point is that reducing the full line buffers from four to two only works if the incoming bottom row is held in a small sliding window and written back into the old top-row buffer after the old pixels are no longer needed.

## Why Two Lines Are Hard

For a stride-1 output centered at row `r`, the convolution needs:

- top row: `r - 1`
- middle row: `r`
- bottom row: `r + 1`

With only two full line buffers, rows `r - 1` and `r` occupy both buffers. The incoming row `r + 1` cannot be written immediately, because it would overwrite `r - 1` before the whole output row has consumed it.

Therefore the incoming row must first live in a small shift/window buffer. Its groups are written into the old top-row buffer only after those top-row columns will never be read again.

## Startup Schedule

1. Read row 0 into `line0`.
2. Read row 1 into `line1`.
3. Stall input for 16 output groups and compute output row 0:
   - top row is zero padding
   - middle row is row 0
   - bottom row is row 1
4. Enter steady streaming at input row 2.

This startup stall is needed because row 0 is still required as the top row for output row 1, so it cannot be overwritten while computing output row 0.

## Steady-State Stride-1 Schedule

While reading input row `b`, compute output row `b - 1`.

At the start of row `b`:

- `top_sel` holds row `b - 2`
- `mid_sel` holds row `b - 1`
- `write_sel = top_sel`

For each input group `g`, containing columns `4g` through `4g+3`:

1. Shift the current row window.
2. Accept four new bottom-row pixels.
3. If `g >= 1`, compute output group `g - 1`, base column `4(g - 1)`.
4. If `g >= 2`, write delayed input group `g - 2` into `write_sel`.

After the last input group:

1. Run one flush group to compute output group 15 with right zero padding.
2. Write the delayed groups 14 and 15 into `write_sel`.
3. Swap selectors:
   - old `mid_sel` becomes next `top_sel`
   - old `write_sel` becomes next `mid_sel`

## Bottom-Row Window For Stride 1

To compute output group `g - 1`, base column `c = 4(g - 1)`, the bottom row needs:

- `c - 1`
- `c`
- `c + 1`
- `c + 2`
- `c + 3`
- `c + 4`

At input group `g`, these are available from:

- one carry pixel from group `g - 2`
- four pixels from group `g - 1`
- the first pixel from group `g`

So the bottom window can be only six useful pixels plus a few staging registers, not a full third line.

## Stride-2 Schedule

Stride-2 output centers are rows `0, 2, 4, ..., 62`.

Startup:

- After reading row 1, compute output center row 0 during a stall, same as stride 1 but only 8 output groups.

Steady state:

- While reading odd input row `b = center + 1`, compute output center row `center`.
- While reading even input rows that are not used as bottom rows for a stride-2 center, only perform the delayed overwrite/writeback needed to roll the two full buffers.

For stride-2 output group with base output column `oc = 4k`, source center columns are:

- `2oc`
- `2oc + 2`
- `2oc + 4`
- `2oc + 6`

The bottom window therefore needs source columns:

- `2oc - 1` through `2oc + 7`

This requires a wider current-row window than stride 1. The important point is still the same: do not build a 3x9 random-read mux from line buffers. Keep the bottom row as shift registers.

## Expected Area Wins

This architecture can reduce area if it removes:

- 4-line random line-buffer read muxes
- duplicate line-buffer selector logic
- some convolution input muxing

It will not automatically reduce the 4-lane MAC or 4-lane cube-root pipeline area. To reach area near 10k, this frontend likely also needs one of:

- simpler activation datapath
- shared cube-root lanes
- more aggressive row-convolution sharing

## Main RTL Risks

1. Overwriting top-row pixels too early.
2. Startup row 0 handling.
3. Last group right-padding handling.
4. Stride-2 bottom-window alignment.
5. Keeping output address order identical to the testbench expectation.

