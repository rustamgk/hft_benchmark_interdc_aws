# Inter-Region Egress Orchestration - Architecture

## Executive Summary

This document describes the complete architecture for inter-region egress orchestration on AWS, where HTTPS traffic from Singapore (ap-southeast-1) is routed through Tokyo (ap-northeast-1) using an EC2-based NAT proxy for egress.

### Key Design Principles

- **Cost-Efficient**: EC2-based NAT vs AWS NAT Gateway (~40% savings)
- **Modular**: Reusable Terraform modules for VPC, EC2, and peering
- **Transparent**: All network traffic visible for debugging and monitoring
- **Scalable**: Easy to add additional regions or instances
- **Learning-Focused**: Understand AWS networking fundamentals

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                        AWS Global Infrastructure                      │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────────────────────────┐    ┌──────────────────────────┐ │
│  │  Singapore (ap-southeast-1)     │    │  Tokyo (ap-northeast-1)  │ │
│  │                                 │    │                          │ │
│  │  ┌───────────────────────────┐  │    │  ┌──────────────────────┐ │
│  │  │  VPC 10.0.0.0/16          │  │    │  │ VPC 10.1.0.0/16      │ │
│  │  │                           │  │    │  │                      │ │
│  │  │ ┌─────────────────────┐   │  │    │  │ ┌────────────────┐   │ │
│  │  │ │ EC2 Client Instance │   │  │    │  │ │  EC2 NAT Proxy │   │ │
│  │  │ │ 10.0.1.10           │   │  │    │  │ │  10.1.1.10     │   │ │
│  │  │ │                     │   │  │    │  │ │                │   │ │
│  │  │ │ • curl (HTTPS API)  │   │  │    │  │ │  • IP Forward  │   │ │
│  │  │ │ • jq, python3       │   │  │    │  │ │  • iptables    │   │ │
│  │  │ │ • mtr, traceroute   │   │  │    │  │ │  • SNAT rule   │   │ │
│  │  │ └─────────────────────┘   │  │    │  │ │                │   │ │
│  │  │                           │  │    │  │ └────────────────┘   │ │
│  │  │ Subnet: 10.0.1.0/24       │  │    │  │                      │ │
│  │  │ IGW: Internet Gateway      │  │    │  │ Subnet: 10.1.1.0/24 │ │
│  │  │ SG: Allow SSH + Peering    │  │    │  │ IGW: Internet GW     │ │
│  │  └───────────────────────────┘  │    │  │ EIP: Elastic IP      │ │
│  │                                 │    │  │ SG: Allow SSH+Peer   │ │
│  └─────────────────────────────────┘    │  └──────────────────────┘ │
│           ▲                             │           ▲                │
│           │ VPC Peering Connection      │           │ Internet       │
│           │ (10.0.0.0/16 <-> 10.1.0.0/16)          │ Gateway        │
│           └─────────────────────────────────────────┘                │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
                            ▼
                   Public Internet
                   (seen from Tokyo IP)
```

---

## Current implementation details (IP-in-IP overlay) — 2025-10-22

This deployment steers Singapore egress via a lightweight IP-in-IP (protocol 4) overlay to the Tokyo NAT host.

- Overlay endpoints
    - Tokyo bastion/NAT: tun0 192.168.250.1/30
    - Singapore client: tun0 192.168.250.2/30
- Routing
    - Singapore default route via tun0 (next-hop 192.168.250.1)
    - Local/VPC/IMDS routes pinned to eth0 to keep instance metadata and intra‑VPC access working
- NAT and forwarding (Tokyo)
    - iptables MASQUERADE on eth0 to SNAT to the Tokyo Elastic IP
    - FORWARD rules allow 10.0.0.0/16 ↔ 0.0.0.0/0; conntrack state respected
- Kernel/network tunings
    - fq qdisc + BBR congestion control; tcp_slow_start_after_idle=0
    - rp_filter disabled on all/eth0/tun0
    - tun0 MTU=1480 and TCPMSS clamp to PMTU (avoid fragmentation)

## Traffic Flow

### Step 1: Client Initiation (Singapore)

```
Singapore EC2 Client (10.0.1.10)
    ↓
Creates HTTPS connection to api.binance.com
    ↓
Packet: SRC=10.0.1.10, DST=1.1.1.1 (example Binance IP)
    ↓
Routing: default route via tun0 (192.168.250.1); local/VPC/IMDS remain on eth0
```

**Source**: 10.0.1.10 (Singapore client)
**Destination**: api.binance.com (Internet)

### Step 2: Transit through VPC Peering

```
Packet enters VPC Peering Connection
    ↓
AWS backbone routes to Tokyo VPC (payload is encapsulated via IP-in-IP over peering)
    ↓
Packet arrives at Tokyo ENI (Elastic Network Interface)
    ↓
Destination: 1.1.1.1 (Binance API)
```

**Route**: Direct AWS backbone (no internet)
**Latency**: 80-100ms (inter-region baseline)
**Cost**: Negligible ($0.02/GB after first 1GB)

### Step 3: NAT Translation (Tokyo)

```
Tokyo EC2 receives packet via peering
    ↓
Checks iptables rule:
  -A POSTROUTING -s 10.0.0.0/16 -j MASQUERADE
    ↓
Applies Source NAT (SNAT):
  Original: SRC=10.0.1.10
  Rewritten: SRC=XX.XX.XX.XX (Tokyo Elastic IP)
    ↓
Packet sent to Internet Gateway
```

**Before NAT**: SRC=10.0.1.10, DST=api.binance.com
**After NAT**: SRC=XX.XX.XX.XX (Tokyo EIP), DST=api.binance.com

### Step 4: Internet Egress (Tokyo)

```
Tokyo Internet Gateway
    ↓
Routes to AWS edge network
    ↓
Packet goes to public internet
    ↓
Seen from Tokyo IP (location = Tokyo, Japan)
```

**Public IP**: Tokyo Elastic IP
**Location**: Tokyo, ap-northeast-1
**ISP**: Amazon (AS16509)

### Step 5: Response Path (Return)

```
api.binance.com receives packet from Tokyo IP
    ↓
Sends response to Tokyo EIP
    ↓
Tokyo IGW receives response
    ↓
Tokyo EC2 receives response
    ↓
Checks SNAT table for reverse translation
    ↓
Translates back: DST=XX.XX.XX.XX → DST=10.0.1.10
    ↓
Routes via peering to Singapore
    ↓
Singapore EC2 receives response
```

**Return Path**: Internet → Tokyo IGW → Peering → Singapore

---

## Component Details

### Singapore VPC Configuration

| Component | Value | Purpose |
|-----------|-------|---------|
| CIDR Block | 10.0.0.0/16 | Network range for Singapore region |
| Subnet | 10.0.1.0/24 | Public subnet for EC2 instance |
| Internet Gateway | Present | For outbound traffic from SGP |
| Route Table | 10.1.0.0/16 → PCX | Route to Tokyo via peering |
| NAT Gateway | None | Not needed (EC2-based NAT instead) |
| Security Group | SSH + Peering | SSH access + traffic to/from Tokyo |

### Tokyo VPC Configuration

| Component | Value | Purpose |
|-----------|-------|---------|
| CIDR Block | 10.1.0.0/16 | Network range for Tokyo region |
| Subnet | 10.1.1.0/24 | Public subnet for NAT proxy |
| Internet Gateway | Present | Primary egress path |
| Route Table | 10.0.0.0/16 → PCX | Route to Singapore via peering |
| NAT Gateway | None | Using EC2-based NAT instead |
| Security Group | SSH + Peering + Internet | Flexible ingress/egress |

### EC2 Instance Configuration

#### Singapore Instance

| Setting | Value | Reason |
|---------|-------|--------|
| Instance Type | t3.small | Cost-effective for testing |
| AMI | Ubuntu 22.04 LTS | Standard Linux distro |
| Source/Dest Check | Enabled | Normal EC2 behavior |
| Public IP | Assigned | SSH access from internet |
| User Data | Client setup script | Install curl, jq, python3, etc. |
| Security Group | Allow SSH + 10.0.0.0/16 + 10.1.0.0/16 | Restricted access |

#### Tokyo Instance

| Setting | Value | Reason |
|---------|-------|--------|
| Instance Type | t3.micro | Cost-efficient NAT/bastion |
| AMI | Ubuntu 22.04 LTS | Standard Linux distro |
| Source/Dest Check | **Disabled** | Allow routing from other IPs |
| Elastic IP | Assigned | Consistent egress IP |
| Public IP | Assigned | SSH access |
| User Data | NAT proxy setup script | Enable IP forwarding + iptables |
| Security Group | Allow SSH + 10.0.0.0/16 + 10.1.0.0/16 | Flexible access |

### VPC Peering Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| Accepter VPC | Singapore (10.0.0.0/16) | Initiates peering |
| Accepter AWS Account | Receiver (Tokyo) | Can be same account |
| Accepter Region | ap-southeast-1 | Singapore region |
| Requester VPC | Tokyo (10.1.0.0/16) | Accepts peering |
| Requester Region | ap-northeast-1 | Tokyo region |
| DNS Resolution | Enabled (both ways) | Enable DNS between regions |
| Route Propagation | Manual (both directions) | 10.0.0.0/16 ↔ 10.1.0.0/16 |

### NAT Proxy Setup (Tokyo EC2)

The Tokyo instance is configured as a NAT proxy via:

```bash
# 1. Enable IP forwarding (kernel parameter)
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# 2. Disable reverse path filtering (allows asymmetric routing)
echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.conf

# 3. Configure iptables SNAT rule
iptables -t nat -A POSTROUTING -s 10.0.0.0/16 -o eth0 -j MASQUERADE

# 4. Persist rules across reboots
netfilter-persistent save
```

**Result**: All traffic from 10.0.0.0/16 appears to come from Tokyo's Elastic IP

Additional tunings applied in this deployment:
- net.core.default_qdisc=fq; net.ipv4.tcp_congestion_control=bbr; net.ipv4.tcp_slow_start_after_idle=0
- net.ipv4.conf.{all,eth0,tun0}.rp_filter=0
- tun0 MTU=1480 and iptables mangle TCPMSS clamp to PMTU

---

## Network Flows

### Scenario 1: HTTPS API Call from Singapore

```
┌─────────────────────────────────────────────────────────────────┐
│                    HTTPS Request Lifecycle                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ 1. Singapore EC2 → DNS Query (api.binance.com)                  │
│    │                                                             │
│    └─→ Public DNS (8.8.8.8) → Returns IP (e.g., 1.1.1.1)       │
│                                                                  │
│ 2. Singapore EC2 → Connect to 1.1.1.1:443                       │
│    │                                                             │
│    └─→ Routing table: 1.1.1.1 is not 10.0.0.0/16               │
│        Use default route → 0.0.0.0/0 → Internet Gateway         │
│                                                                  │
│ 3. Singapore IGW → Packet routing                               │
│    │                                                             │
│    └─→ Packet: SRC=10.0.1.10, DST=1.1.1.1                      │
│        Route: Not in local CIDR → Goes to IGW                   │
│        IGW sees: "Send this to public internet"                 │
│                                                                  │
│ BUT WAIT! We want this via Tokyo!                               │
│    │                                                             │
│    └─→ Actually, default route points to peering for Tokyo      │
│        Default routes: 0.0.0.0/0 → IGW only for emergency      │
│        Primary: All public traffic goes via Tokyo NAT            │
│                                                                  │
│ 4. Packet → Tokyo NAT Proxy via VPC Peering                     │
│    │                                                             │
│    └─→ Peering: SRC=10.0.1.10, DST=1.1.1.1                     │
│        AWS backbone → Arrives at Tokyo EC2                      │
│                                                                  │
│ 5. Tokyo NAT Proxy: SNAT Translation                            │
│    │                                                             │
│    └─→ iptables POSTROUTING rule triggers                       │
│        MASQUERADE: SRC=10.0.1.10 → SRC=YY.YY.YY.YY (Tokyo EIP)  │
│                                                                  │
│ 6. Tokyo IGW: Public Internet Access                            │
│    │                                                             │
│    └─→ Packet: SRC=YY.YY.YY.YY, DST=1.1.1.1                    │
│        Route: YY.YY.YY.YY is public IP → IGW routes to internet │
│                                                                  │
│ 7. Public Internet: Request Delivery                            │
│    │                                                             │
│    └─→ Binance API sees request from Tokyo IP (YY.YY.YY.YY)     │
│        Cannot see original client (10.0.1.10)                   │
│                                                                  │
│ 8. Response: Binance → Tokyo (reverse path)                     │
│    │                                                             │
│    └─→ Response: DST=YY.YY.YY.YY (Tokyo EIP)                    │
│        Tokyo IGW → Tokyo EC2                                     │
│                                                                  │
│ 9. Tokyo EC2: Reverse SNAT Translation                          │
│    │                                                             │
│    └─→ NAT table lookup: "What sent from YY.YY.YY.YY to 1.1.1.1│
│        Answer: 10.0.1.10"                                        │
│        Rewrite: DST=YY.YY.YY.YY → DST=10.0.1.10                │
│                                                                  │
│ 10. Peering: Response → Singapore                               │
│    │                                                             │
│    └─→ Response: SRC=1.1.1.1, DST=10.0.1.10                    │
│        Peering connection: Tokyo → Singapore                     │
│        Arrives at Singapore EC2                                  │
│                                                                  │
│ 11. Singapore EC2: Process Response                             │
│    │                                                             │
│    └─→ Application receives HTTPS response                      │
│        Application "sees" response from 1.1.1.1                 │
│        Application unaware of Tokyo routing                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Latency Analysis

### Expected Latencies

```
Component                        Latency
─────────────────────────────────────────
Singapore EC2 (no traffic)       0-10ms (baseline)
Singapore → Tokyo peering        80-100ms (inter-region)
Tokyo SNAT processing            1-5ms
Tokyo EC2 → Binance (internet)   50-100ms
TLS handshake                     10-30ms
HTTPS API response               varies
─────────────────────────────────────────
Total (first request)            ~270ms via‑Tokyo; ~130-160ms direct SG (cold)
Total (subsequent requests)      ~72-76ms from SG (keepalive); ~5-6ms from Tokyo vantage
```

### Why Is Latency High?

1. **Singapore-Tokyo Distance**: ~80-100ms baseline
2. **HTTPS Overhead**: TLS handshake adds ~20-30ms
3. **Internet Routing**: Binance API location adds 50-100ms
4. **NAT Processing**: ~1-5ms per packet

**This is expected and normal** for inter-region routing.

---

## Cost Breakdown

### EC2-Based NAT Approach (This Project)

```
Scenario: Run for 1 week continuous

EC2 Instances:
  · 2 × t3.small @ $0.026/hr
  · 7 days × 24 hours = 168 hours
  · Cost: 2 × 168 × $0.026 = $8.74

Data Transfer:
  · Inter-region peering: First 1GB free (~$0.02/GB after)
  · Internet egress: First 1GB free (~$0.09/GB after)
  · Typical week: <1GB for testing → $0

Total: ~$9/week
```

### vs AWS NAT Gateway Approach

```
Scenario: Run for 1 week continuous

NAT Gateway:
  · Hourly charge: $0.45/hr × 168 hours = $75.60
  · Data processing: $0.045/GB
  · Typical week: $0.05-0.10/GB = $5-10

Total: ~$85-90/week

Difference: 40% savings with EC2-based NAT!
```

---

## Security Considerations

### VPC Peering Security

- **Traffic Isolation**: Peering uses AWS backbone, not internet
- **Encryption**: None by default (AWS backbone is secure)
- **Network ACLs**: Can restrict traffic between VPCs
- **Security Groups**: Granular control over allowed traffic

### EC2 NAT Security

- **No SSH Forward**: SSH only from your IP (restricted SG)
- **No Privileged Access**: iptables rules set at boot time
- **Minimal Attack Surface**: Only curl + SSH exposed
- **Elastic IP**: Static IP for consistent access

### Production Recommendations

1. **Restrict SSH**: Use security group to limit SSH to your IP
2. **VPN Access**: Use AWS Systems Manager Session Manager instead of SSH
3. **Encryption**: Enable encryption for peering if data is sensitive
4. **Logging**: Enable VPC Flow Logs for traffic analysis
5. **Monitoring**: CloudWatch metrics on instance performance

---

## Scaling Considerations

### Adding More Regions

To add a 3rd region (e.g., Sydney):

1. Create new VPC module for Sydney (10.2.0.0/16)
2. Create new EC2 module for NAT proxy
3. Create peering connections: Sydney ↔ Singapore, Sydney ↔ Tokyo
4. Configure routes in all 3 VPCs
5. Update security groups to allow inter-region traffic

### Adding More Instances

To add multiple clients in Singapore:

1. Create additional subnet (10.0.2.0/24, 10.0.3.0/24, etc.)
2. Launch EC2 instances in each subnet
3. All route to Tokyo NAT proxy via peering
4. Load distribution happens naturally

### Load Balancing

For high-traffic scenarios:

1. Use Application Load Balancer in Singapore
2. Route through Tokyo NAT proxy
3. Or: Create multiple Tokyo NAT instances with NLB

---

## Constraints and Limitations

### Terraform Limitations

- **State Management**: Stored locally (use S3 for production)
- **Concurrent Operations**: Sequential by default
- **Version Pinning**: Hard-coded AWS provider version

### Network Limitations

- **Peering Limit**: 125 peering connections per VPC (fine for testing)
- **ENI Limit**: 5 elastic IPs per account (default, can be increased)
- **Latency**: Cannot reduce Singapore-Tokyo baseline (~80ms)

### AWS Limitations

- **Free Tier**: 750 hours global, first 1GB data transfer free
- **Region Availability**: Not all AWS services in all regions
- **Instance Types**: t3.small best for cost/performance testing

---

## Validation Approach

### What We Test

1. **Connectivity**: Can all instances communicate?
2. **Latency**: Is latency in expected range?
3. **Path**: Does traffic go through peering?
4. **Geolocation**: Is egress IP from Tokyo?
5. **Reliability**: Do results repeat consistently?

### How We Test

```bash
# From Singapore instance
curl -w "%{time_total}s\n" https://api.binance.com/api/v3/time  # Latency
curl -s ipinfo.io | jq '.city'                                 # Geolocation
mtr -c 5 -r api.binance.com                                    # Path analysis
```

### Success Criteria

- ✅ Latency 200-400ms (acceptable for testing)
- ✅ Geolocation shows Tokyo
- ✅ Path shows Singapore → Tokyo → Internet
- ✅ All tests pass 100% of the time

---

## Troubleshooting Guide

### Issue: VPC Peering Not Accepting

**Symptom**: Peering connection stuck in "pending-acceptance" state

**Root Cause**: Peering acceptance not configured in target region

**Solution**:
```hcl
# Add accepter configuration in Tokyo provider
resource "aws_vpc_peering_connection_accepter" "tokyo" {
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
  auto_accept              = true
}
```

### Issue: Traffic Not Going Through Tokyo

**Symptom**: Geolocation shows Singapore IP, not Tokyo

**Root Cause**: NAT rule not configured or iptables not persisted

**Solution**:
```bash
# SSH to Tokyo instance
sudo iptables -t nat -L -n
# Should show: MASQUERADE rule for 10.0.0.0/16

# If missing, add it:
sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/16 -o eth0 -j MASQUERADE
sudo netfilter-persistent save
```

### Issue: High Latency (>1 second)

**Symptom**: curl taking >1000ms

**Root Cause**: 
- Network congestion
- Tokyo EC2 CPU limited (t3.small burst exhausted)
- DNS resolution slow

**Solution**:
- Run at different time (test during low traffic periods)
- Increase instance type (t3.medium)
- Pre-resolve DNS: `curl --resolve api.binance.com:443:1.1.1.1`

---

## Conclusion

This architecture provides a cost-effective, educational demonstration of inter-region egress orchestration using EC2-based NAT proxies. It's suitable for learning and testing, but for production use, consider:

- Dedicated NAT instances with auto-scaling
- AWS NAT Gateway for managed service
- VPN for encrypted inter-region traffic
- CloudWatch monitoring and alerting

---

**Document Version**: 1.0
**Last Updated**: October 2025
**Maintained By**: HFT Benchmark Project
