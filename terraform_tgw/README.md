# Option B: Transit Gateway (TGW) Centralized Egress via Tokyo

This Terraform stands up a TGW-based architecture where all outbound Internet traffic from the Singapore VPC is steered to Tokyo and egresses via a NAT Gateway in Tokyo.

## High-level
- TGW in ap-southeast-1 and ap-northeast-1, peered
- Singapore VPC attached to SG TGW
- Tokyo egress VPC attached to Tokyo TGW
- Route 0.0.0.0/0 from SG TGW attachment to Tokyo TGW attachment
- NAT Gateway in Tokyo public subnet provides egress IP (Elastic IP)

## Modules/Files
- main.tf – providers, TGW, TGW peering, VPC attachments, NATGW
- variables.tf – basic params
- outputs.tf – useful IPs and IDs

## Notes
- Costs: TGW hours + data processing (inter-region TGW peering) + NAT Gateway hours/GB + EIP + EC2 if bastion
- Latency should be comparable to WireGuard when under similar routing conditions; verify via validation
