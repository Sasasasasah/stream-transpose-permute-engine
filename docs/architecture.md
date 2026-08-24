# Stream Transpose and Permutation Architecture

The engine is organized as two independent slices in a structural full wrapper.
Each slice contains four transpose tiles, a fixed-latency command column, four
single-entry result buffers, and a combinational tile permutation engine.

Transpose operates on two byte planes across 16 stream segments. A captured
tile result must reside in its result buffer for a full cycle before Permute may
read it. Same-cycle release and replacement use read-old/write-new ordering.

The permutation supports four fixed tile phases. It preserves lane order within
each segment while routing complete tile results to destination tiles.
