# Quick Start Guide

Get up and running in 15 minutes.

## 1. Prerequisites (5 min)

```bash
# Install Terraform
brew install terraform  # macOS
# or visit https://www.terraform.io/downloads

# Configure AWS credentials
aws configure

# Create SSH key pair
aws ec2 create-key-pair --key-name hft-benchmark --region ap-southeast-1 \
  --query 'KeyMaterial' --output text > ~/.ssh/hft-benchmark.pem
chmod 600 ~/.ssh/hft-benchmark.pem

# Generate public key from private key (required for Terraform)
ssh-keygen -y -f ~/.ssh/hft-benchmark.pem > ~/.ssh/hft-benchmark.pub
chmod 644 ~/.ssh/hft-benchmark.pub
```

## 2. Deploy (5 min)

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Wait for output showing public IPs.

## 3. Test (5 min)

```bash
# Get Singapore instance IP
SINGAPORE_IP=$(terraform output -raw singapore_instance_public_ip)

# SSH in
ssh -i ~/.ssh/hft-benchmark.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$SINGAPORE_IP

# Test egress (from Singapore instance)
curl -w "Time: %{time_total}s\n" https://api.binance.com/api/v3/time
curl -s ipinfo.io | jq '.city, .country'  # Should show Tokyo, JP
```

## Troubleshooting SSH Connection

If you can't login, try these steps:

### 1. Verify the key file exists and has correct permissions
```bash
ls -la ~/.ssh/hft-benchmark.pem
# Should show: -rw------- (600 permissions)
# If not, fix it:
chmod 600 ~/.ssh/hft-benchmark.pem
```

### 2. Verify the instance is running
```bash
SINGAPORE_IP=$(terraform output -raw singapore_instance_public_ip)
echo "Singapore IP: $SINGAPORE_IP"

# Check instance status
aws ec2 describe-instances --region ap-southeast-1 \
  --query 'Reservations[0].Instances[0].[PublicIpAddress,State.Name]'
# Should show the IP and "running"
```

### 3. Check security group allows SSH
```bash
# Get the security group ID
SG_ID=$(terraform output -raw singapore_security_group_id)

# Check if SSH (port 22) is allowed
aws ec2 describe-security-groups --group-ids $SG_ID --region ap-southeast-1 \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
```

### 4. Check the key is correct
```bash
# Verify key format (should be RSA PRIVATE KEY)
head -1 ~/.ssh/hft-benchmark.pem

# Try SSH with verbose output to see what's happening
ssh -v -i ~/.ssh/hft-benchmark.pem ubuntu@$SINGAPORE_IP
```

### 5. If key still doesn't work, recreate it
```bash
# Delete old key from AWS
aws ec2 delete-key-pair --key-name hft-benchmark --region ap-southeast-1

# Create new key
aws ec2 create-key-pair --key-name hft-benchmark --region ap-southeast-1 \
  --query 'KeyMaterial' --output text > ~/.ssh/hft-benchmark.pem
chmod 600 ~/.ssh/hft-benchmark.pem

# Try SSH again (might need to wait 30 seconds for key to sync)
sleep 30
ssh -i ~/.ssh/hft-benchmark.pem ubuntu@$SINGAPORE_IP
```

## Results

If you see:
- ✅ Response time 200-400ms
- ✅ City: Tokyo
- ✅ Country: JP

**SUCCESS!** 🎉 Your traffic is egressing from Tokyo.

## Next Steps

1. Run full validation: `cd ../validation && ./run_validation.sh`
2. Review architecture: `cat ../docs/ARCHITECTURE.md`
3. Cleanup when done: `cd ../terraform && terraform destroy`
