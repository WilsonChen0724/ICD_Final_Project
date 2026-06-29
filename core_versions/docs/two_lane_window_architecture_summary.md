# Two-Lane + Window Architecture Summary

## Goal

Reduce convolution hardware area by computing two output pixels per cycle instead of four, while using a small sliding window to reuse nearby pixels.

The expected tradeoff is:

```text
Area: lower arithmetic replication
Time: higher cycle count
AT: only improves if area reduction is larger than time increase
```

## High-Level Dataflow

1. Keep streaming input at 32 bits per accepted cycle.
   Each input word contains 4 image pixels.

2. Store incoming rows into rolling line buffers.
   At least 4 full line buffers are still useful for streaming overlap, because the design may write a new row while computing from older rows.

3. Build a small horizontal window from the line buffers.
   For two adjacent output pixels, each source row needs 4 consecutive pixels:

   ```text
   output c:     pixels c-1, c,   c+1
   output c+1:   pixels c,   c+1, c+2
   shared set:   pixels c-1, c, c+1, c+2
   ```

   Across 3 rows, this is 12 pixels per two-output group.

4. Compute two convolution outputs per cycle.
   Use two lanes:

   ```text
   lane0 -> output column c
   lane1 -> output column c+1
   ```

5. Push two clamped values into the activation pipeline.
   The square and cube-root pipeline also become two lanes.

6. Emit only `o_out_valid1` and `o_out_valid2`.
   Keep `o_out_valid3` and `o_out_valid4` low.

## Pipeline Stages

Recommended pipeline:

```text
Cycle A: Fetch/update window and compute 2 lanes of 3x3 products
Cycle B: Partial sums per lane
Cycle C: Final sum + round + clamp
Cycle D: Square
Cycle E-J: 6-stage cube-root binary search pipeline
```

This is similar to the current deep pipeline, but with two lanes instead of four.

## Stride = 1 Flow

For each output row:

1. Start from output column 0.
2. For each two-column group:
   ```text
   c = 0, 2, 4, ..., 62
   ```
3. Load or shift the 3-row window.
4. Compute outputs `(row, c)` and `(row, c+1)`.
5. Advance the window by 2 columns.

Boundary cases:

```text
c = 0       needs left zero padding
c = 62      lane1 touches right boundary
row = 0     needs top zero padding
row = 63    needs bottom zero padding
```

Interior cases can use a faster raw line-buffer read without padding checks.

## Stride = 2 Flow

Stride=2 output map is 32x32.

For each output row:

1. Only compute when the original center row is even.
2. Output columns map to original columns:

   ```text
   output c     -> original center column 2*c
   output c+1   -> original center column 2*(c+1)
   ```

3. Two output lanes require original center columns separated by 2.
   Their 3x3 windows overlap less than stride=1:

   ```text
   lane0 uses cols 2c-1, 2c,   2c+1
   lane1 uses cols 2c+1, 2c+2, 2c+3
   shared only at 2c+1
   ```

Because overlap is smaller, the window advantage is weaker for stride=2.

## Why Area May Not Improve Enough

In our experiment, the area2 family did not reduce area meaningfully, while total time increased a lot.

Likely reasons:

```text
1. The four-lane arithmetic was not the only dominant area.
2. Extra stall/control/pending registers added overhead.
3. The two-lane pipeline still needed similar buffering and cube-root control.
4. Lower throughput directly increased total execution time.
5. DC may have already optimized the original four-lane arithmetic well.
```

## When This Architecture Is Worth Trying

It is worth trying if:

```text
area drops by close to 40-50%
clock period stays similar
testbench allows ready-based input stalls
AT is the main metric instead of only runtime
```

It is not attractive if:

```text
area stays close to the four-lane version
time nearly doubles
ready stalls complicate streaming control
```

## Current Recommendation

Based on measured results, the better direction is:

```text
Keep 4-lane throughput
Use shared-window convolution frontend
Optimize common-case interior pixel fetch
Search the best synthesis clock constraint
```

The current best candidate is the 4-lane shared-window deep pipeline, not the two-lane area2 architecture.
