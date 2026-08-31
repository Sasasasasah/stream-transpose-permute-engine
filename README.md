# Stream Transpose and Permutation Engine

A cycle-aware RTL/C++ implementation of a stream-oriented 32x32 transpose
engine built from pipelined 8x8 transpose units, result buffers, and
deterministic tile permutation.

This repository is a deterministic RTL/C++ architecture prototype for studying
and verifying stream transpose/permutation behavior; it is not production
accelerator IP or a physical-design implementation.

## Features

- Four-stage transpose command pipeline
- Four 8x8 transpose tiles with BF16/FP16 byte-plane organization
- Four-entry result-buffer array with read-old/write-new reuse
- Four-phase deterministic tile permutation
- East/West stream selector support
- Dual-hemisphere structural wrapper
- 32x32 transpose and continuous initiation interval of four cycles
- Lightweight cycle-aware C++ model
- RTL/CModel canonical trace comparison
- Command legality and fault containment tests

## Architecture

```text
sxm_full
|-- sxm_slice[0]
|   |-- command decode
|   |-- transpose control pipeline
|   |-- transpose tiles
|   |-- result buffers
|   `-- permute engine
`-- sxm_slice[1]
```

Within one slice:

```text
Stream Input -> Transpose Pipeline -> Result Buffer -> Permute -> Stream Output
```

## 32x32 Transpose Schedule

A 32x32 matrix is decomposed into a 4x4 grid of 8x8 sub-blocks. The four-stage
pipeline forms a diagonal capture wave:

```text
w0: B00
w1: B10 B01
w2: B20 B11 B02
w3: B30 B21 B12 B03
w4:     B31 B22 B13
w5:         B32 B23
w6:             B33
```

The next matrix may start every four cycles. The verification environment checks
both complete matrix reconstruction and read-old/write-new buffer reuse during
the overlap cycle. The 32x32 shape and II=4 timing describe the current
prototype configuration and schedule.

## Project Structure

```text
rtl/       Synthesizable Verilog RTL
cmodel/    Lightweight cycle-aware C++ model
tb/        RTL testbenches
scripts/   Windows batch regression entry points
docs/      Architecture and interface notes
```

## Documentation

- [Architecture](docs/architecture.md)
- [Interface](docs/interface.md)

## Quick Start

From the repository root on Windows:

```bat
scripts\run_sxm_all_regression.bat
```

## Verification

Regression coverage includes transpose correctness, atomic valid/consume,
control-pipeline timing, result-buffer timing, permutation, 32x32 transpose,
continuous II=4 operation, RTL/CModel trace alignment, dual-hemisphere
independence, and command legality.

Expected final result:

```text
SXM_ALL_REGRESSION TEST_PASS
```

This is a personal educational RTL/CModel architecture project. Verify that
you have the appropriate rights before publishing any derivative work.
