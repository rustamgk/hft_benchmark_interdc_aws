# Cost estimate: IP-in-IP overlay via Tokyo vs TGW centralized egress

This document provides a simple, auditable cost model you can plug into the AWS Pricing Calculator. Numbers below are reference estimates; always verify current pricing for your account and regions.

Assumptions
- Regions: ap-southeast-1 (Singapore), ap-northeast-1 (Tokyo)
- Instances: Ubuntu 22.04, on-demand
- Data path: Singapore → Tokyo (cross-region) → Internet
- Prices are approximate and may vary by region/time; use the formulas and substitute current rates.

## Components and unit prices (approximate)

Current solution (IPIP + EC2 NAT in Tokyo)
- EC2 t3.micro (Tokyo bastion/NAT): ~$0.0104/hr ≈ $7.50/mo
- EC2 t3.small (Singapore client): ~$0.0208/hr ≈ $15.00/mo
- EBS volumes (8 GB gp3 each): $0.10/GB-month → ~$1.60/mo for two
- Elastic IP attached (Tokyo): ~$0.005/hr ≈ $3.60/mo
- VPC Peering (inter-region) data transfer: ~$0.02/GB
- Inter-region data transfer (AWS) may also apply per GB; verify combined rate for your account
- Data transfer to Internet from Tokyo: region tiered (example: ~$0.09/GB for first 10 TB) — check current Tokyo egress price

Note: If you add an AWS NAT Gateway (not required for this overlay), include:
- NAT Gateway hourly: ~ $0.048/hr ≈ $35/mo
- NAT Gateway data processing: ~ $0.045/GB
Recommendation: Prefer EC2 NAT for this pattern to avoid these fixed and per‑GB costs.

TGW centralized egress alternative (typical pattern)
- AWS Transit Gateway hourly per attachment: ~$0.05/hr/attachment
  - 2 VPC attachments (Singapore and Tokyo): ~$0.10/hr ≈ $72/mo
- TGW data processing: ~$0.02/GB
- (If inter-region TGW peering is needed) TGW inter-region data: ~$0.05/GB
- Egress NAT Gateway in Tokyo (required in egress VPC): ~$0.048/hr ≈ $35/mo + ~$0.045/GB processed
- You can often remove the EC2 NAT in this design

## Cost formulas

Let V be your monthly data volume through the path (in GB/month).

IPIP overlay (current)
- Fixed monthly: EC2 (t3.micro + t3.small) + EIP + EBS ≈ $7.5 + $15 + $3.6 + $1.6 = ~$27.7/mo
- Variable per-GB: Inter-region data (peering) + Tokyo egress ≈ ($0.02 + egress_tokyo_per_gb) * V
- If NAT Gateway added: add ~$35 fixed + $0.045 * V (not recommended here)

TGW centralized egress
- Fixed monthly: 2 TGW attachments + NAT GW hourly ≈ $72 + $35 = ~$107/mo
- Variable per-GB: TGW processing + (if inter-region TGW peering) + NAT GW processing + Tokyo egress
  - ≈ ($0.02 + [0 or $0.05] + $0.045 + egress_tokyo_per_gb) * V

Where egress_tokyo_per_gb is your current ap-northeast-1 Internet egress rate (tiered; plug from calculator).

## Example comparison (illustrative)

Example inputs:
- Volume: 100 GB/day ≈ 3,000 GB/mo
- Tokyo egress price (tier 1): $0.09/GB

IPIP overlay
- Fixed: ~$27.7/mo
- Variable: ($0.02 + $0.09) * 3000 = $0.11 * 3000 = $330
- Total: ~$358/mo

TGW centralized egress (no inter-region TGW peering) — same region TGW only
- Fixed: ~$107/mo
- Variable: ($0.02 + $0.045 + $0.09) * 3000 = $0.155 * 3000 = $465
- Total: ~$572/mo

TGW with inter-region TGW peering (if applicable)
- Fixed: ~$107/mo
- Variable: ($0.02 + $0.05 + $0.045 + $0.09) * 3000 = $0.205 * 3000 = $615
- Total: ~$722/mo

Conclusion (at this traffic level): IPIP + EC2 NAT is significantly cheaper than TGW centralized egress. TGW may be preferable for scale, operations, or advanced routing, but it costs more per GB and per hour.

Quick summary (current config)
- Fixed: ~ $28/mo (2 EC2 + EIP + EBS)
- Variable: ~$0.02/GB (peering) + Tokyo egress tier price

## How to calculate in AWS Pricing Calculator

Create two scenarios and plug exact region prices:
1) IPIP overlay (current)
   - 2 EC2 instances: t3.micro (Tokyo), t3.small (Singapore)
   - 2 EBS gp3 8GB
   - 1 Elastic IP attached (public IPv4 hourly)
   - VPC Peering: add expected monthly data transfer cross-region (pricing category: Data Transfer → Inter-Region)
   - Internet data transfer from Tokyo: add expected egress volume
   - (Optional) NAT Gateway: set to zero if you plan to remove it

2) TGW centralized egress
   - Transit Gateway with 2 VPC attachments (hours per month)
   - TGW data processing (GB/month)
   - (If cross-region TGW peering) TGW inter-region peering data (GB/month)
   - 1 NAT Gateway (hours/month) + data processing (GB/month)
   - Internet data transfer from Tokyo (GB/month)

Export both to CSV/PDF and attach to your deliverables for auditability.

## Optimization tips
- Remove unused NAT Gateway to save ~$35/mo + data fees
- Right-size EC2 types; T-class burstable often sufficient
- Consider spot for the Tokyo bastion/NAT if acceptable
- If traffic grows large and you need managed high-availability NAT, revisit TGW+NAT GW despite higher cost