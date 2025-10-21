# Validation Testing Framework

This directory contains the comprehensive validation framework for the Inter-Region Egress Orchestration project.

## Quick Start

```bash
cd validation
./run_validation.sh

# Optional flags (env vars):
#   PIN_TOKYO_POP=1   # pin CDN POP in Tokyo via --resolve
#   KEEPALIVE=1       # add an extra keepalive latency phase
#   TLS13=1           # force TLS 1.3 for latency phases
#   BREAKDOWN=1       # also emit CSV with curl timing breakdown
```

## What It Tests

The framework runs multiple phases of validation:

### 1. Preflight Checks (`01-preflight.sh`)

Verifies all prerequisites are in place:
- DNS resolution working
- Internet connectivity
- Required tools installed (curl, jq, python3)

### 2. Baseline Latency (`02-baseline-latency.sh`)

Measures HTTPS latency to Binance API:
- Makes 100 requests to `api.binance.com`
- Captures full request time including TLS handshake
- Computes percentiles (min, max, mean, p50, p95, p99)
- Saves raw latencies and statistics
- Optional: `TLS13=1` forces TLS 1.3, `BREAKDOWN=1` outputs `latencies_breakdown.csv`

### 2a. Overlay RTT (`02a-overlay-rtt.sh`)

Measures the ICMP RTT across the inter-region overlay tunnel:
- Pings the Tokyo tunnel peer (e.g., 192.168.250.1)
- Useful to correlate HTTP latency with raw path RTT

### 2b. Keepalive Latency (`02b-latency-keepalive.sh`)

Measures HTTP latency while reusing a single TCP/TLS connection:
- Issues multiple requests in one curl process using `--next`
- Captures per-request timing and writes `latency_stats_keepalive.json`
- Optional: respects `RESOLVE_*` pinning and `TLS13=1`

### 3. Path Verification (`03-path-verification.sh`)

Shows the network path:
- Uses `mtr` (best) or `traceroute` as fallback
- Displays hop-by-hop latency
- Verifies traffic goes through peering connection

### 4. Geolocation (`04-geolocation.sh`)

Confirms egress IP is from Tokyo:
- Queries ipinfo.io for geolocation
- Verifies city = Tokyo
- Verifies country = JP

### 5. Report Generation (`06-generate-report.sh`)

Creates comprehensive Markdown report:
- Summarizes all test results
- Includes latency statistics
- Includes geolocation data
- Professional formatted output

## Expected Results

### Success Indicators

✅ **Latency**: 200-400ms (singapore → tokyo → internet)
✅ **Geolocation**: City = Tokyo, Country = JP
✅ **Path**: Shows Singapore → Tokyo → Internet
✅ **All phases**: Complete without errors

### Typical Latency Distribution

```
Min:    180-200ms    (direct singapore-tokyo)
P50:    250-300ms    (median)
P95:    300-350ms    (95th percentile)
P99:    400-450ms    (99th percentile)
Max:    400-500ms    (worst case)
```

## Output Files

Each run creates a timestamped results directory:

```
validation/results/20251016-120000/
├── 01-preflight.log              # Preflight output
├── 02-latency.log                        # Latency measurements
├── 02a-overlay-rtt.log                    # Overlay RTT ping output (if run)
├── latencies.txt                          # Raw per-request totals (cold)
├── latencies_breakdown.csv                # Curl timing breakdown (optional)
├── latency_stats.json                     # Computed stats (cold)
├── latencies_keepalive.txt                # Raw per-request totals (warm)
├── latencies_keepalive_breakdown.csv      # Keepalive timing breakdown
├── latency_stats_keepalive.json           # Computed stats (warm)
├── 03-path.log                   # Network path
├── 04-geolocation.log            # Geolocation output
├── geolocation.json              # IP geolocation data
├── 06-report.log                 # Report generation log
└── VALIDATION_REPORT.md          # Final report
```

## Running Individual Tests

You can run specific phases:

```bash
# Preflight only
bash validation/01-preflight.sh

# Latency measurement
bash validation/02-baseline-latency.sh /tmp

# Path verification
bash validation/03-path-verification.sh

# Geolocation
bash validation/04-geolocation.sh /tmp

# Report generation
bash validation/06-generate-report.sh /tmp
```

## Customizing Tests

### Change Number of Latency Requests

```bash
bash validation/02-baseline-latency.sh /tmp 500  # 500 requests instead of 100
```

### Manual Single Request

```bash
# Test latency
curl -w "Time: %{time_total}s\n" https://api.binance.com/api/v3/time

# Test geolocation
curl -s ipinfo.io | jq '.city, .country, .ip'

# Test path
mtr -c 5 -r api.binance.com
```

## Troubleshooting

### Latency Too High

Possible causes:
- High internet latency (check `mtr` output)
- Singapore-Tokyo region latency baseline (80-100ms)
- Tokyo instance overloaded (check CPU)
- Network congestion (retry at different time)

**Fix**: Run test multiple times, check mtr output for packet loss

### Geolocation Not Tokyo

Possible causes:
- Egress not going through Tokyo NAT proxy
- Elastic IP not properly associated
- iptables rule not configured

**Fix**: SSH to Tokyo instance, check `sudo iptables -t nat -L -n`

### Preflight Checks Failing

Possible causes:
- Binance API unreachable
- DNS not working
- Required tools not installed

**Fix**: Check internet connectivity, run `apt-get install -y curl jq python3`

## Performance Tuning

### To Reduce Test Time

```bash
# Run fewer iterations
bash validation/02-baseline-latency.sh /tmp 50  # 50 requests
```

### To Get Better Statistics

```bash
# Run more iterations
bash validation/02-baseline-latency.sh /tmp 1000  # 1000 requests
```

## Continuous Monitoring

Run tests periodically:

```bash
# Every hour
0 * * * * cd /path/to/validation && ./run_validation.sh

# Every 6 hours
0 */6 * * * cd /path/to/validation && ./run_validation.sh
```

## Interpreting Results

### Latency Analysis

- **Min/Max**: Shows range of observed latencies
- **Mean**: Average of all measurements
- **Median (P50)**: Middle value (50th percentile)
- **P95**: 95% of requests faster than this
- **P99**: 99% of requests faster than this

### Network Path

- **First hop**: Your local network
- **Middle hops**: Singapore EC2 → Tokyo EC2 (via peering)
- **Last hops**: Tokyo IGW → Internet backbone

### Geolocation

- **Expected**: City = Tokyo, Country = JP
- **IP**: Should be Tokyo Elastic IP
- **ISP**: AWS (ap-northeast-1)

---

**Note**: All tests use HTTPS to capture real-world latency including TLS handshake overhead.

## Advanced performance tips

- Enable BBR + fq qdisc (now automated via user-data): reduces latency/jitter under load.
- MSS clamping at the NAT (Tokyo) avoids fragmentation on the IPIP tunnel.
- Tunnel MTU set to 1480 to account for IPIP overhead.
- Prefer POP pinning (PIN_TOKYO_POP=1) to keep a Tokyo edge.
- Use KEEPALIVE=1 and optionally TLS13=1 for fairer app-like measurements.
