# Validation Comparison: Via-Tokyo Overlay vs Direct Singapore Baseline

This document captures the current “via-Tokyo” results and provides a placeholder to add the direct-from-Singapore baseline for an apples-to-apples comparison.

Date: 2025-10-21

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

## Comparison summary

- Egress location: Via Tokyo = Tokyo, JP (35.76.36.216); Baseline = Singapore, SG (54.254.160.207)
- P50 delta (ms): 130.30 vs 541.67 → Δ = -411.37 ms (baseline faster)
- P95 delta (ms): 219.31 vs 678.56 → Δ = -459.25 ms (baseline faster)
- Qualitative path differences:
	- Via Tokyo adds the Singapore↔Tokyo leg and NAT on the Tokyo bastion
	- Baseline goes direct from Singapore to the Internet

## Interpretation

- Expect the Via-Tokyo scenario to add Singapore↔Tokyo leg plus NAT processing; this generally increases TLS end-to-end times compared to direct Singapore egress.
- The overlay centralizes egress for compliance/control and produces a Tokyo-sourced IP as required by the design.

---
Maintenance tip: Re-run both validations when instance types, network conditions, or regions change. Store both result folders and update this comparison with the new timestamps and statistics.
