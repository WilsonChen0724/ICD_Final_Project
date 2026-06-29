# Core Version Archive

This folder collects the major RTL versions explored during optimization.

## 00_final

- `core_2line_bypass_fifo_pixpipe_lanepix_drain11.v`
- Final selected architecture.
- Uses two line buffers, input-row bypass FIFO, lane-pixel pipeline, digit cube-root activation, output address counter, and `drain_count == 11`.

## 01_baseline_streaming

Early working versions and baseline references:

- `core_original_root.v`
- `core_streaming.v`
- `core_streaming_linebuf_v_1.v`
- `core_multicycle.v`

These were used to validate correctness and explore row-at-a-time or multi-cycle control before the later streaming/pipelined versions.

## 02_pipeline_experiments

Streaming pipeline experiments:

- `core_streaming_pipelined.v`
- `core_streaming_pipelined_area2.v`
- `core_streaming_pipelined_deep.v`
- `core_streaming_pipelined_deep_area2.v`
- `core_streaming_pipelined_deep_cubeopt.v`

These versions explored deeper MAC/cube-root pipelining, area cleanup, and cube-root datapath variants.

## 03_convshare_digitcube

Convolution-sharing and digit-cube versions:

- `core_streaming_pipelined_deep_convshare.v`
- `core_streaming_pipelined_deep_convshare_baseaddr_rowsum.v`
- `core_streaming_pipelined_deep_convshare_digitcube.v`
- `core_streaming_pipelined_deep_convshare_digitcube_rowsum.v`

These versions reduced duplicated convolution/address logic and replaced heavier cube-root logic with digit-by-digit arithmetic cube root.

## 04_2line_bypass

Two-line buffer and bypass experiments:

- `core_2line_window_experiment.v`
- `core_2line_window_digitcube.v`
- `core_2line_bypass_fifo_rowsum.v`
- `core_2line_bypass_fifo_pixpipe.v`
- `core_2line_bypass_fifo_pixpipe_addrctr.v`
- `core_2line_bypass_fifo_pixpipe_addrctr_drain11.v`
- `core_2line_bypass_fifo_pixpipe_lanepix.v`
- `core_2line_bypass_fifo_pixpipe_lanepix_drain11.v`

This line of work produced the final selected architecture. The key area/timing improvement came from using a two-line circular buffer with input-row bypass FIFO and a lane-pixel pipeline.

## 05_mac_multicycle_rejected

- `core_streaming_digitcube_mac2cycle.v`
- `core_streaming_digitcube_mac3cycle.v`

These versions tried to reduce MAC hardware by spreading computation across more cycles. They were rejected because total runtime and/or area were worse.

## docs

Architecture notes and report snippets.

