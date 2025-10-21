#!/usr/bin/env python3
"""
Analyze latency measurements and compute percentiles
"""

import sys
import json

def analyze_latencies(latencies):
    """Compute latency statistics"""
    latencies = sorted([float(x) for x in latencies if x.strip()])
    
    n = len(latencies)
    mean = sum(latencies) / n
    
    def percentile(p):
        idx = int(n * (p / 100))
        return latencies[min(idx, n-1)]
    
    return {
        "count": n,
        "min": round(min(latencies) * 1000, 2),
        "max": round(max(latencies) * 1000, 2),
        "mean": round(mean * 1000, 2),
        "median": round(percentile(50) * 1000, 2),
        "p95": round(percentile(95) * 1000, 2),
        "p99": round(percentile(99) * 1000, 2),
    }

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: analyze_latency.py <latency_file>")
        sys.exit(1)
    
    with open(sys.argv[1]) as f:
        latencies = f.readlines()
    
    stats = analyze_latencies(latencies)
    print(json.dumps(stats, indent=2))
