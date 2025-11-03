# AWS Inter-Region Benchmark - Complete Guide

## Quick latency snapshot (warm/keepalive) — 2025-10-22 (tuned)

These are the latest warm (connection reuse) results from the validation suite. See `docs/VALIDATION_COMPARISON.md` for full context and cold vs warm breakdowns.

| Scenario                 | Egress Region | Egress IP      | Warm P50 (ms) | Warm P95 (ms) | Warm P99 (ms) | Run folder                                      |
|--------------------------|---------------|----------------|---------------|---------------|---------------|-------------------------------------------------|
| Direct SG baseline       | Singapore, SG | 54.254.160.207 | 72.09         | 74.67         | 151.64        | `validation/results/20251022-020550-baseline/` |
| Via Tokyo (pinned POP)   | Tokyo, JP     | 35.76.36.216   | 76.05         | 79.57         | 278.12        | `validation/results/20251022-020050/`          |
| Tokyo vantage (direct)   | Tokyo, JP     | 35.76.36.216   | 5.48          | 6.40          | 6.58         | `validation/results/20251022-022358-tokyo/`    |

Notes
- “Warm” reflects typical app behavior with connection reuse (KEEPALIVE=1). Medians for Singapore-origin scenarios converge near overlay RTT + server time (~72–76 ms).
- The Tokyo vantage run is included for perspective when originating directly in Tokyo.
- Details, cold-start numbers, and methodology: `docs/VALIDATION_COMPARISON.md`.

## Overview

This project demonstrates inter-region egress orchestration on AWS, where HTTPS traffic from Singapore (ap-southeast-1) is routed through a Tokyo (ap-northeast-1) EC2 instance acting as a NAT proxy, allowing traffic to egress with a Tokyo IP address.

**Key Characteristics:**
- ✅ Single EC2 in Singapore VPC (client)
- ✅ Single EC2 in Tokyo VPC (NAT proxy)
- ✅ VPC peering between regions
- ✅ Traffic routes through AWS backbone (private peering)
- ✅ Egress to internet from Tokyo IP
- ✅ Infrastructure as Code (Terraform)

## Architecture

See `docs/ARCHITECTURE.md` for complete architecture details and ASCII diagram.

Quick summary:
```
Singapore EC2 (10.0.1.10)
    ↓
VPC Peering Connection
    ↓
Tokyo EC2 NAT Proxy (10.1.1.10) with Elastic IP
    ↓
Internet Gateway
    ↓
Public Internet (traffic seen from Tokyo IP)
```

## Project Structure

```
hft_benchmark_interdc_aws/
├── terraform/                 # Infrastructure as Code
│   ├── main.tf               # Main configuration
│   ├── modules/
│   │   ├── vpc/              # VPC module (subnets, IGW, routing)
│   │   ├── ec2/              # EC2 instance module
│   │   └── peering/          # VPC peering module
│   ├── user-data/
│   │   ├── singapore.sh      # Singapore instance setup
│   │   └── tokyo.sh          # Tokyo NAT proxy setup
│   ├── terraform.tfvars      # Variable overrides
│   └── .gitignore            # Terraform files to ignore
├── validation/               # Testing framework
│   ├── run_validation.sh     # Main test orchestrator
│   ├── 01-preflight.sh       # Pre-flight checks
│   ├── 02-baseline-latency.sh # Latency measurement
│   ├── 03-path-verification.sh # Path analysis (mtr, traceroute)
│   ├── 04-geolocation.sh     # Geolocation verification
│   ├── 06-generate-report.sh # Report generation
│   ├── analyze_latency.py    # Statistical analysis
│   ├── README.md             # Validation framework docs
│   └── results/              # Test results (created on first run)
├── scripts/                  # Utility scripts (for future use)
├── docs/                     # Documentation
│   └── ARCHITECTURE.md       # Architecture details
└── README.md                 # This file
```

## Prerequisites

### AWS Account

- ✅ **Any AWS account** (free tier CAN do multi-region!)
  - AWS Free Tier: 750 EC2 hours **GLOBAL** across all regions
  - This task uses ~10 hours, costs **~$0**
  - See `FREE_TIER_EXPLANATION.md` and `PAID_ACCOUNT_FAQ.md` for details
- ✅ Credentials configured: `aws configure`
- ✅ Permissions: EC2, VPC, VPC Peering

### Local Tools

- ✅ Terraform >= 1.0
- ✅ AWS CLI
- ✅ SSH client (for EC2 access)

### SSH Key Pair

Create an SSH key pair for EC2 access:
```bash
# Create private key
aws ec2 create-key-pair --key-name hft-benchmark --region ap-southeast-1 \
  --query 'KeyMaterial' --output text > ~/.ssh/hft-benchmark.pem
chmod 600 ~/.ssh/hft-benchmark.pem

# Generate public key (required for Terraform to upload to both regions)
ssh-keygen -y -f ~/.ssh/hft-benchmark.pem > ~/.ssh/hft-benchmark.pub
chmod 644 ~/.ssh/hft-benchmark.pub
```

## Deployment

### Step 1: Initialize Terraform

```bash
cd terraform
terraform init
```

This will:
- Download AWS provider
- Initialize local state
- Validate configuration

### Step 2: Plan Deployment

```bash
terraform plan
```

Review the output. You should see:
- 2 VPCs (Singapore, Tokyo)
- 2 EC2 instances (t3.small)
- 1 VPC peering connection
- Security groups and routing

### Step 3: Deploy Infrastructure

```bash
terraform apply
```

This will create:
- Singapore VPC (10.0.0.0/16) with EC2 client
- Tokyo VPC (10.1.0.0/16) with EC2 NAT proxy
- VPC peering connection with automatic acceptance
- All required security groups and routes

**Note the output:**
```
Outputs:
singapore_instance_public_ip = "XX.XX.XX.XX"
tokyo_instance_public_ip = "YY.YY.YY.YY"
tokyo_nat_elastic_ip = "ZZ.ZZ.ZZ.ZZ"
peering_connection_id = "pcx-xxxxxxxx"
```

Save these values for testing.

### Step 4: SSH into Singapore Instance

```bash
SINGAPORE_IP=$(terraform output -raw singapore_instance_public_ip)
ssh -i ~/.ssh/hft-benchmark.pem ubuntu@$SINGAPORE_IP
```

### Step 5: Verify Setup

```bash
# From Singapore instance, verify Tokyo IP
curl -s ipinfo.io | jq '.ip, .city, .country'

# Should show Tokyo IP (from tokyo_nat_elastic_ip)
# Should show city: Tokyo, country: JP
```

## Testing

### Option 1: Quick Manual Test

```bash
# SSH to Singapore instance
ssh -i ~/.ssh/hft-benchmark.pem ubuntu@$SINGAPORE_IP

# Test latency
curl -w "Time: %{time_total}s\n" https://api.binance.com/api/v3/time

# Verify egress IP is Tokyo
curl -s ipinfo.io | jq '.city, .country'
```

### Option 2: Automated Validation Suite

```bash
cd validation
./run_validation.sh
```

This runs:
1. **Preflight checks** - Verify all components are up
2. **Baseline latency** - Measure HTTPS latency to Binance API
3. **Path verification** - Show network path with mtr
4. **Geolocation** - Confirm egress IP is Tokyo
5. **Report generation** - Create VALIDATION_REPORT.md

See `validation/README.md` for full testing documentation.

## Validation Outputs

### Success Indicators

✅ **Latency**: 200-400ms (Singapore to Tokyo to Internet)
✅ **Geolocation**: City = Tokyo, Country = JP
✅ **Path**: Should show Singapore → Tokyo → Internet
✅ **Response**: Valid JSON from Binance API

### Expected Results

```json
{
  "latency": {
    "min": 180,
    "max": 450,
    "mean": 280,
    "median": 250,
    "p95": 380,
    "p99": 420
  },
  "geolocation": {
    "ip": "XX.XX.XX.XX",
    "city": "Tokyo",
    "country": "JP",
    "region": "Tokyo"
  }
}
```

## Troubleshooting

### Issue: Can't SSH to Singapore Instance

**Problem**: SSH times out or connection refused
**Solution**:
```bash
# Check security group allows SSH
aws ec2 describe-security-groups --group-ids sg-xxxxx --region ap-southeast-1

# Check instance is running
aws ec2 describe-instances --region ap-southeast-1 --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]'
```

### Issue: VPC Peering Connection Failed

**Problem**: Instances can't communicate across regions
**Solution**:
```bash
# Verify peering connection is active
aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids pcx-xxxxx --region ap-southeast-1

# Check route tables
aws ec2 describe-route-tables --region ap-southeast-1
aws ec2 describe-route-tables --region ap-northeast-1
```

### Issue: Egress IP Still Shows Singapore

**Problem**: Traffic not going through Tokyo NAT
**Solution**:
```bash
# SSH to Tokyo instance
TOKYO_IP=$(terraform output -raw tokyo_instance_public_ip)
ssh -i ~/.ssh/hft-benchmark.pem ubuntu@$TOKYO_IP

# Check iptables rule
sudo iptables -t nat -L -n

# Check IP forwarding
cat /proc/sys/net/ipv4/ip_forward  # Should be 1

# Check routing on Singapore instance
ip route
```

### Issue: Data Transfer Between Regions Not Working

**Problem**: Routes not set up correctly
**Solution**:
```bash
# From Singapore instance
ping 10.1.1.10  # Should reach Tokyo instance

# If ping fails, check security groups
# Should allow ICMP from 10.0.0.0/16 to 10.1.0.0/16
```

## Cleanup

To destroy all resources and avoid charges:

```bash
cd terraform
terraform destroy
```

This will delete:
- Both VPCs and all subnets
- Both EC2 instances
- VPC peering connection
- All security groups and routes

## Architecture Components

### Singapore VPC

- **CIDR**: 10.0.0.0/16
- **Subnet**: 10.0.1.0/24 (public)
- **Instance**: t3.small running Ubuntu 22.04
- **Role**: HTTPS client (traffic source)
- **Security**: SSH access + outbound to Tokyo VPC

### Tokyo VPC

- **CIDR**: 10.1.0.0/16
- **Subnet**: 10.1.1.0/24 (public)
- **Instance**: t3.small running Ubuntu 22.04
- **Role**: NAT proxy with iptables SNAT
- **Security**: SSH access + inbound from Singapore VPC + Internet Gateway

### VPC Peering

- **Connection**: Singapore ↔ Tokyo
- **DNS Resolution**: Enabled
- **Route Propagation**: Automatic
- **MTU**: Standard (1500 bytes)

## Traffic Flow

1. Singapore EC2 initiates HTTPS to Binance API
2. Packet enters Tokyo VPC via peering connection
3. Tokyo EC2 (NAT proxy) processes packet with iptables SNAT rule:
   - Source IP changed from 10.0.1.10 to Tokyo Elastic IP
   - Packet sent to Internet Gateway
4. Internet sees request from Tokyo Elastic IP
5. Response comes back to Tokyo Elastic IP
6. NAT proxy translates back to 10.0.1.10
7. Response reaches Singapore EC2

## Cost Estimation

### EC2-Based NAT vs AWS NAT Gateway

```
Scenario: 24-hour testing

EC2-Based NAT:
- 2x t3.small instances: $0.0260/hour × 48 hours = ~$1.25
- Data transfer: ~100 MB = ~$0 (first 1GB free)
- Total: ~$1.25

AWS NAT Gateway:
- Gateway hourly charge: $0.45 × 24 hours = ~$10.80
- Data processing: $0.045 per GB × 0.1 GB = ~$0.45
- Total: ~$11.25

Savings: 40% reduction with EC2-based NAT!
```

### Long-Term Cost (1 Month)

```
EC2-Based NAT:
- 2 instances running 24/7: $0.0260 × 730 hours × 2 = ~$38
- Data transfer: ~1 GB = ~$0 (assuming standard usage)
- Total: ~$38/month

AWS NAT Gateway:
- Gateway: $0.45 × 730 hours = ~$328.50
- Data: $0.045/GB (varies)
- Total: ~$480+/month
```

## Key Files

| File | Purpose |
|------|---------|
| `terraform/main.tf` | Main Terraform configuration |
| `terraform/modules/vpc/main.tf` | VPC setup |
| `terraform/modules/ec2/main.tf` | EC2 instances |
| `terraform/modules/peering/main.tf` | VPC peering |
| `terraform/user-data/singapore.sh` | Client setup script |
| `terraform/user-data/tokyo.sh` | NAT proxy setup script |
| `validation/run_validation.sh` | Main test orchestrator |
| `docs/ARCHITECTURE.md` | Architecture documentation |

## Next Steps

1. ✅ Review architecture in `docs/ARCHITECTURE.md`
2. ✅ Deploy infrastructure: `terraform apply`
3. ✅ Run validation: `validation/run_validation.sh`
4. ✅ Review test results in `VALIDATION_REPORT.md`
5. ✅ Cleanup: `terraform destroy`

## Additional Resources

- **Terraform Documentation**: https://www.terraform.io/docs
- **AWS VPC Peering**: https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html
- **AWS NAT Gateway**: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html
- **Binance API**: https://binance-docs.github.io/apidocs/

## Support

For issues or questions:
1. Check `DEPLOYMENT_CHECKLIST.md` for step-by-step verification
2. Review `validation/README.md` for testing details
3. See troubleshooting section above
4. Check AWS Console for resource status

---

**Project Status**: ✅ Complete and ready to deploy
**Last Updated**: October 2025
