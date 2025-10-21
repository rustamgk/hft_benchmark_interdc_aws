#!/bin/bash
set -e

echo "=== Tokyo Bastion + HTTP CONNECT Proxy Setup ==="

# Update system
apt-get update
apt-get upgrade -y

# Install required tools
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl \
  jq \
  python3 \
  net-tools \
  squid \
  ca-certificates

# Configure Squid as a minimal HTTPS CONNECT proxy
SQUID_CONF="/etc/squid/squid.conf"
cp "$SQUID_CONF" "${SQUID_CONF}.bak"
cat > "$SQUID_CONF" << 'EOF'
http_port 3128

# Allow only VPC CIDRs (Singapore 10.0.0.0/16, Tokyo 10.1.0.0/16)
acl allowed_vpcs src 10.0.0.0/16 10.1.0.0/16
http_access allow allowed_vpcs

# Deny everything else
http_access deny all

# Only allow CONNECT to common TLS ports
acl SSL_ports port 443 8443
acl Safe_ports port 80 443 8443
http_access allow CONNECT SSL_ports

# Keep logs minimal
access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
cache_store_log none

# No caching (we're only tunneling)
cache deny all

# Increase request size limits as a safeguard
request_body_max_size 10 MB

dns_v4_first on
EOF

systemctl enable squid
systemctl restart squid

echo "=== Bastion + Proxy setup complete ==="
echo "Squid listening on: 0.0.0.0:3128 (restricted to VPC CIDRs)"
