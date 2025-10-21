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
    "min": 265.87,
    "max": 406.26,
    "mean": 276.6,
    "median": 270.25,
    "p95": 309.67,
    "p99": 406.26
  }

Warm (connection reuse / keepalive) Latency Statistics (milliseconds):
  {
    "count": 100,
    "min": 72.83,
    "max": 267.29,
    "mean": 75.92,
    "median": 73.78,
    "p95": 77.56,
    "p99": 267.29
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
