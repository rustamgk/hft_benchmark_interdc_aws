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
    "min": 59.3,
    "max": 68.34,
    "mean": 62.44,
    "median": 62.07,
    "p95": 66.21,
    "p99": 68.34
  }

Warm (connection reuse / keepalive) Latency Statistics (milliseconds):
Note: Excludes first request (cold-start/connection establishment overhead)
  {
    "count": 99,
    "min": 4.92,
    "max": 8.31,
    "mean": 5.97,
    "median": 5.97,
    "p95": 6.69,
    "p99": 8.31
  }

### Phase 3: Path Verification
✓ Network path verified

### Phase 4: Geolocation

Geolocation Data:
  {
    "ip": "57.180.173.66",
    "hostname": "ec2-57-180-173-66.ap-northeast-1.compute.amazonaws.com",
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
