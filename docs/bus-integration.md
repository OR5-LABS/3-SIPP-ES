# Bus Integration

3-SIPP-ES presents a simple native memory interface out of the core, and ships an
**AXI4-Lite** bridge for dropping the core into a standard SoC fabric.

## Native interface

The core drives a lightweight valid/ready instruction-fetch port and a
load/store port with byte strobes. The reference SoC (`three_sipp_es_soc.sv`) wires
these directly to on-chip memories and peripherals — the smallest, lowest-latency
option.

## AXI4-Lite bridge

`rtl/three_sipp_es_axi_lite.sv` is an **AXI4-Lite master** that adapts the core's
load/store interface to the five AXI channels (AW / W / B / AR / R) with
`VALID`/`READY` handshakes and byte strobes (`WSTRB`). It carries one
outstanding transaction and propagates the AXI response (`OKAY` / `SLVERR`) back
to the core.

The bridge is an **optional** standalone block: the default SoC and the
compliance path never instantiate it, so enabling AXI never changes the core's
behaviour.

### Verification

`build.sh axi` exercises the bridge against a WSTRB-aware slave-memory BFM that
injects wait states on every channel, checking:

- word and sub-word (byte / half, via `WSTRB`) read/write integrity;
- untouched-cell preservation;
- error handling — a poisoned address returns `SLVERR` on both read and write,
  with a load-bearing negative control (expecting `OKAY` there fails).

Expected output:

```
AXI: PASS
```

Use the AXI bridge to attach 3-SIPP-ES to an AXI interconnect, or keep the native
interface for a tightly-coupled memory subsystem.
