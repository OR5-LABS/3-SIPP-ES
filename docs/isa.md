# Instruction Set

3-SIP-ESR implements **RV32IMAC** plus the `B` bit-manipulation and `Zcb`
code-size extensions.

## Base and standard extensions

| Extension | Description |
|-----------|-------------|
| **RV32I** | base 32-bit integer instruction set |
| **M** | integer multiply / divide (`MUL`, `MULH*`, `DIV*`, `REM*`) |
| **A** | atomics — `LR.W` / `SC.W` and the nine `AMO<op>.W` operations |
| **C** | compressed 16-bit instructions |
| **Zicsr** | control-and-status register access |

## Bit-manipulation (`B`)

The full ratified `B` set is supported:

| Sub-extension | Instructions |
|---------------|--------------|
| **Zba** | address generation — `SH1ADD`, `SH2ADD`, `SH3ADD` |
| **Zbb** | basic bit-manip — `ANDN`, `ORN`, `XNOR`, `CLZ`, `CTZ`, `CPOP`, `MIN[U]`, `MAX[U]`, `SEXT.B/H`, `ZEXT.H`, `ROL`, `ROR[I]`, `ORC.B`, `REV8` |
| **Zbc** | carry-less multiply — `CLMUL`, `CLMULH`, `CLMULR` |
| **Zbs** | single-bit — `BCLR`, `BEXT`, `BINV`, `BSET` (+ immediates) |

## Code size (`Zcb`)

The `Zcb` compressed encodings shrink common sequences: compressed sub-word
loads/stores (`c.lbu`, `c.lhu`, `c.lh`, `c.sb`, `c.sh`), and compressed
`c.zext.*` / `c.sext.*` / `c.not` / `c.mul`.

## Atomics (`A`)

`LR.W` sets a word reservation; `SC.W` succeeds only if the reservation is
still valid; the nine `AMO<op>.W` variants
(`swap`, `add`, `and`, `or`, `xor`, `min`, `max`, `minu`, `maxu`) perform a
read-modify-write to a naturally-aligned word.

## Misaligned access

Naturally-misaligned loads and stores are handled **in hardware** as a
two-beat memory sequence rather than trapping.

## Privileged ISA

Machine mode is always present. The `SECURE` configuration adds User mode and
the `N` user-trap extension. See
[Privilege & Security](privilege-and-security.md) and [CSRs](csrs.md).

## Conformance

The RV32IMAC(+C) behaviour is checked against the official RISC-V unit tests and
lock-step against a golden RV32IM ISA model — see [Verification](verification.md).
