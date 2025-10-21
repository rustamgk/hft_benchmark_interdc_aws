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
    "min": 126.7,
    "max": 272.19,
    "mean": 135.58,
    "median": 131.03,
    "p95": 153.45,
    "p99": 272.19
  }

Warm (connection reuse / keepalive) Latency Statistics (milliseconds):
  {
    "count": 100,
    "min": 69.56,
    "max": 214.48,
    "mean": 79.38,
    "median": 71.94,
    "p95": 203.94,
    "p99": 214.48
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
