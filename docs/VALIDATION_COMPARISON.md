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

## Scenario B — Direct Singapore Baseline (to be collected)

Once the public baseline instance is provisioned and reachable, run:

```
cd validation
./run_validation_baseline.sh
```

Then record:
- Egress IP (should be Singapore region IP)
- Geolocation (City=Singapore, Country=SG)
- Latency statistics (same methodology as Scenario A)
- Path (direct from Singapore to Internet)

## Comparison summary (to fill after baseline run)

- Egress location: Via Tokyo = Tokyo, JP; Baseline = Singapore, SG
- P50 delta (ms): [baseline_p50] vs 541.67 → Δ = [baseline_p50 - 541.67]
- P95 delta (ms): [baseline_p95] vs 678.56 → Δ = [baseline_p95 - 678.56]
- Qualitative path differences: [insert brief mtr/traceroute observations]

## Interpretation

- Expect the Via-Tokyo scenario to add Singapore↔Tokyo leg plus NAT processing; this generally increases TLS end-to-end times compared to direct Singapore egress.
- The overlay centralizes egress for compliance/control and produces a Tokyo-sourced IP as required by the design.

---
Maintenance tip: Re-run both validations when instance types, network conditions, or regions change. Store both result folders and update this comparison with the new timestamps and statistics.
