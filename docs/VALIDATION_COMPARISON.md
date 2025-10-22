# Validation Comparison: Via-Tokyo Overlay vs Direct Singapore Baseline

This document captures the current “via-Tokyo” results and provides a placeholder to add the direct-from-Singapore baseline for an apples-to-apples comparison.

Note: You can optionally run the keepalive latency phase (connection reuse) by setting KEEPALIVE=1 when invoking the validation runners. When present, keepalive statistics will be included in the per-run `VALIDATION_REPORT.md`.

Date: 2025-10-21

## Quick comparison (p50/p95/p99) — 2025-10-22

| Scenario               | Egress        | Egress IP      | P50 (ms) | P95 (ms) | P99 (ms) | Run folder                                     |
|------------------------|---------------|----------------|----------|----------|----------|-----------------------------------------------|
| Via Tokyo (pinned POP) | Tokyo, JP     | 35.76.36.216   | 270.23   | 283.97   | 295.79   | `validation/results/20251022-004612/`          |
| Direct SG baseline     | Singapore, SG | 54.254.160.207 | 132.52   | 266.66   | 305.73   | `validation/results/20251022-005628-baseline/` |

Notes (2025-10-22)
- Delta (Via Tokyo pinned vs Baseline): P50 +137.71 ms, P95 +17.31 ms — consistent with added SG↔TYO leg; POP pinning maintained Tokyo edge.
- Egress verification: Tokyo run geolocates to Tokyo (35.76.36.216); Baseline run geolocates to Singapore (54.254.160.207).

## Quick comparison (cold vs keepalive) — 2025-10-22 (flags ON)

Flags: PIN_TOKYO_POP=1, KEEPALIVE=1, TLS13=1, BREAKDOWN=1

| Scenario               | Egress        | Egress IP      | Cold P50 | Cold P95 | Cold P99 | Warm P50 | Warm P95 | Warm P99 | Run folder                                     |
|------------------------|---------------|----------------|----------|----------|----------|----------|----------|----------|-----------------------------------------------|
| Via Tokyo (pinned POP) | Tokyo, JP     | 35.76.36.216   | 270.25   | 309.67   | 406.26   | 73.78    | 77.56    | 267.29   | `validation/results/20251022-012549/`          |
| Direct SG baseline     | Singapore, SG | 54.254.160.207 | 131.03   | 153.45   | 272.19   | 71.94    | 203.94   | 214.48   | `validation/results/20251022-012945-baseline/` |

Overlay RTT (from Via‑Tokyo run): avg ≈ 68.70 ms (`02a-overlay-rtt.log`)

Observations
- Warm (keepalive) collapses TLS handshake RTTs; medians approach overlay RTT + server time (~72–74 ms), validating the overlay’s efficiency.
- Cold via‑Tokyo remains ~270 ms median—dominated by SG↔TYO RTT in handshake and CDN edge, even when pinned.
- Baseline warm P95 shows a few outliers (to ~204 ms); median remains ~72 ms. Cold baseline remains best for cold-starts due to lack of the extra inter‑region leg.

### Interpretation (2025‑10‑22)

- Keepalive effectiveness: With connection reuse, Via‑Tokyo and Baseline both converge to ~72–74 ms median, which is within a few ms of the measured overlay RTT (~68.7 ms) plus upstream server time. This confirms the overlay itself isn’t adding meaningful overhead beyond the inter‑region path.
- Cold start cost: The ~270 ms cold median for Via‑Tokyo reflects the extra SG↔TYO RTT baked into TCP+TLS handshakes. Baseline cold remains faster (median ~131 ms) because it avoids the inter‑region hop on handshake.
- Tail behavior: Occasional warm outliers (Via‑Tokyo p99 ~267 ms; Baseline warm p95 ~204 ms) likely stem from CDN/backend variability rather than the overlay. POP pinning removes cross‑region POP effects, reducing variance versus unpinned runs.
- Egress correctness: Geolocation and IPs confirm egress in the intended regions (Tokyo for Via‑Tokyo, Singapore for Baseline).
- Tuning not yet applied: These runs did not include kernel/MTU/MSS tunings (BBR/fq, MTU 1480, MSS clamp). Applying them should tighten tails further under load and avoid fragmentation‑related stalls.

Recommended next steps
1) Recreate instances to pick up tunings (BBR/fq, MTU 1480, MSS clamp), then rerun the same matrix with flags (PIN_TOKYO_POP=1, KEEPALIVE=1, TLS13=1, BREAKDOWN=1) to confirm tail improvements.
2) If encryption is required, A/B test WireGuard overlay versus IPIP; expect similar medians with a small overhead in CPU and a few ms in handshake.
3) If you need a managed, scalable and inspectable architecture across many VPCs, pilot TGW + Egress VPC and re‑measure; performance should be comparable, with cleaner ops but higher per‑GB costs.

## Quick comparison (cold vs keepalive) — 2025-10-22 (tuned)

Context: Instances recreated with BBR/fq, MTU 1480, and TCPMSS clamp. Flags defaulted ON (PIN_TOKYO_POP for Via‑Tokyo; KEEPALIVE/TLS13/BREAKDOWN for both).

| Scenario               | Egress        | Egress IP      | Cold P50 | Cold P95 | Cold P99 | Warm P50 | Warm P95 | Warm P99 | Run folder                                     |
|------------------------|---------------|----------------|----------|----------|----------|----------|----------|----------|-----------------------------------------------|
| Via Tokyo (pinned POP) | Tokyo, JP     | 35.76.36.216   | 275.42   | 300.01   | 312.62   | 76.05    | 79.57    | 278.12   | `validation/results/20251022-020050/`          |
| Direct SG baseline     | Singapore, SG | 54.254.160.207 | 133.98   | 153.81   | 263.22   | 72.09    | 74.67    | 151.64   | `validation/results/20251022-020550-baseline/` |

Overlay RTT (from Via‑Tokyo run): avg ≈ 70.01 ms (`02a-overlay-rtt.log`)

Observations (tuned)
- Warm medians remain ~72–76 ms, closely tracking overlay RTT, indicating minimal overlay overhead with connection reuse.
- Baseline warm tail tightened markedly (p95 ~74.67 ms) versus earlier runs, consistent with tunings reducing queueing/fragmentation risks.
- Via‑Tokyo warm p99 still shows a rare outlier (~278 ms), likely upstream/CDN variance; medians stay stable.
- Cold medians/p95 did not materially change (as expected), since cold is dominated by handshake RTTs rather than kernel/MTU tuning.

## Quick comparison (p50/p95)

| Scenario                | Egress         | Egress IP       | P50 (ms) | P95 (ms) | Run folder                                    |
|-------------------------|----------------|-----------------|----------|----------|-----------------------------------------------|
| Via Tokyo (unpinned)    | Tokyo, JP      | 35.76.36.216    | 541.67   | 678.56   | `validation/results/20251021-191127/`         |
| Via Tokyo (pinned POP)  | Tokyo, JP      | 35.76.36.216    | 270.43   | 283.01   | `validation/results/20251021-225359/`         |
| Direct SG baseline      | Singapore, SG  | 54.254.160.207  | 130.30   | 219.31   | `validation/results/20251021-215657-baseline/`|

## Scenario A — Via Tokyo (IPIP overlay + EC2 NAT)

- Source host: Singapore client (private), default route via tun0
- Path: Singapore → VPC peering → Tokyo bastion (NAT) → Internet
- Egress IP (Tokyo EIP): 35.76.36.216
- Geolocation: Tokyo, JP
- Run folder: `validation/results/20251021-191127/`

Latency statistics (100 HTTPS requests to api.binance.com)
- Min: 531.78 ms
- Median (P50): 541.67 ms
- Mean: 555.52 ms
- P95: 678.56 ms
- P99: 795.21 ms
- Max: 795.21 ms

Path and geolocation
- Path: Verified (see `03-path.log` in the run folder)
- Geolocation: City=Tokyo, Country=JP (see `geolocation.json`)

Notes
- Validation source: `validation/results/20251021-191127/latency_stats.json`, `.../geolocation.json`, `.../VALIDATION_REPORT.md`

## Scenario B — Direct Singapore Baseline

- Source host: Singapore baseline (public), direct egress via IGW
- Path: Singapore → Internet
- Egress IP: 54.254.160.207
- Geolocation: Singapore, SG
- Run folder: `validation/results/20251021-215657-baseline/`

Latency statistics (100 HTTPS requests to api.binance.com)
- Min: 125.96 ms
- Median (P50): 130.30 ms
- Mean: 138.01 ms
- P95: 219.31 ms
- P99: 308.56 ms
- Max: 308.56 ms

Path and geolocation
- Path: See `validation/results/20251021-215657-baseline/03-path.log`
- Geolocation: City=Singapore, Country=SG (see `geolocation.json`)

## Scenario C — Via Tokyo (Pinned to Tokyo POP)

- Source host: Singapore client (private), default route via tun0
- Path: Singapore → VPC peering → Tokyo bastion (NAT) → Internet
- POP pinning: api.binance.com resolved on Tokyo and pinned via `curl --resolve`
- Egress IP (Tokyo EIP): 35.76.36.216
- Geolocation: Tokyo, JP
- Run folder: `validation/results/20251021-225359/`

Latency statistics (100 HTTPS requests to api.binance.com)
- Min: 265.32 ms
- Median (P50): 270.43 ms
- Mean: 271.39 ms
- P95: 283.01 ms
- P99: 295.99 ms
- Max: 295.99 ms

Overlay RTT (Singapore → Tokyo tunnel IP)
- 10 pings to 192.168.250.1: min/avg/max/mdev = 68.609 / 68.659 / 68.718 / 0.027 ms
- Source: `validation/results/20251021-225359/02a-overlay-rtt.log`

## Comparison summary

- Egress locations:
	- Via Tokyo (unpinned): Tokyo, JP (35.76.36.216)
	- Via Tokyo (pinned): Tokyo, JP (35.76.36.216)
	- Baseline: Singapore, SG (54.254.160.207)

- Baseline vs Via Tokyo (unpinned):
	- P50: 130.30 vs 541.67 → Δ = -411.37 ms (baseline faster)
	- P95: 219.31 vs 678.56 → Δ = -459.25 ms (baseline faster)

- Baseline vs Via Tokyo (pinned):
	- P50: 130.30 vs 270.43 → Δ = +140.13 ms (via Tokyo pinned slower, expected extra SG↔TYO leg)
	- P95: 219.31 vs 283.01 → Δ = +63.70 ms

- Via Tokyo improvement from pinning POP:
	- P50: 541.67 → 270.43 (Δ = -271.24 ms)
	- P95: 678.56 → 283.01 (Δ = -395.55 ms)

- Qualitative path differences:
	- Via Tokyo adds the Singapore↔Tokyo leg and NAT on the Tokyo bastion
	- POP pinning ensures the Tokyo egress IP reaches a Tokyo CloudFront edge, removing the “Tokyo→Singapore POP” mismatch
	- Baseline goes direct from Singapore to the Internet

## Interpretation

- Expect the Via-Tokyo scenario to add Singapore↔Tokyo leg plus NAT processing; this generally increases TLS end-to-end times compared to direct Singapore egress.
- The overlay centralizes egress for compliance/control and produces a Tokyo-sourced IP as required by the design.

---
Maintenance tip: Re-run both validations when instance types, network conditions, or regions change. Store both result folders and update this comparison with the new timestamps and statistics.
