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
    "min": 127.8,
    "max": 263.22,
    "mean": 137.09,
    "median": 133.98,
    "p95": 153.81,
    "p99": 263.22
  }

Warm (connection reuse / keepalive) Latency Statistics (milliseconds):
  {
    "count": 100,
    "min": 70.37,
    "max": 151.64,
    "mean": 73.17,
    "median": 72.09,
    "p95": 74.67,
    "p99": 151.64
  }

### Phase 3: Path Verification
✓ Network path verified

### Phase 4: Geolocation

Geolocation Data:
  {
    "ip": "54.254.160.207",
    "hostname": "ec2-54-254-160-207.ap-southeast-1.compute.amazonaws.com",
    "city": "Singapore",
    "region": "Singapore",
    "country": "SG",
    "loc": "1.2897,103.8501",
    "org": "AS16509 Amazon.com, Inc.",
    "postal": "018989",
    "timezone": "Asia/Singapore",
    "readme": "https://ipinfo.io/missingauth"
  }

### Phase 5: Report Generation
✓ Report generated successfully

## Conclusion

All validation phases completed successfully. The inter-region egress orchestration is working as expected.

---
Generated: $(date)
