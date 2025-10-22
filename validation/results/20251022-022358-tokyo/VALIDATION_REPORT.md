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
    "min": 59.52,
    "max": 208.13,
    "mean": 79.14,
    "median": 66.45,
    "p95": 144.33,
    "p99": 208.13
  }

Warm (connection reuse / keepalive) Latency Statistics (milliseconds):
  {
    "count": 100,
    "min": 4.78,
    "max": 64.58,
    "mean": 6.14,
    "median": 5.48,
    "p95": 6.4,
    "p99": 64.58
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
