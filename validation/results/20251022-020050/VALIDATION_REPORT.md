# Validation Report

## Executive Summary

This report contains the results of the validation suite for the Inter-Region Egress Orchestration project.

## Test Results

### Phase 1: Preflight Checks
✓ All preflight checks passed

### Phase 2: Latency Measurements

Cold (new connection each request) Latency Statistics (milliseconds):
  {
    "count": 100,
    "min": 270.59,
    "max": 312.62,
    "mean": 278.03,
    "median": 275.42,
    "p95": 300.01,
    "p99": 312.62
  }

Warm (connection reuse / keepalive) Latency Statistics (milliseconds):
  {
    "count": 100,
    "min": 74.88,
    "max": 278.12,
    "mean": 78.15,
    "median": 76.05,
    "p95": 79.57,
    "p99": 278.12
  }

### Phase 3: Path Verification
✓ Network path verified

### Phase 4: Geolocation

Geolocation Data:
  {
    "ip": "35.76.36.216",
    "hostname": "ec2-35-76-36-216.ap-northeast-1.compute.amazonaws.com",
    "city": "Tokyo",
    "region": "Tokyo",
    "country": "JP",
    "loc": "35.6895,139.6917",
    "org": "AS16509 Amazon.com, Inc.",
    "postal": "101-8656",
    "timezone": "Asia/Tokyo",
    "readme": "https://ipinfo.io/missingauth"
  }

### Phase 5: Report Generation
✓ Report generated successfully

## Conclusion

All validation phases completed successfully. The inter-region egress orchestration is working as expected.

---
Generated: $(date)
