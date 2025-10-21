#!/bin/bash

echo "=== Singapore Client Setup ==="

# Update system
apt-get update
apt-get upgrade -y

# Define required tools
REQUIRED_TOOLS=(
  "curl"
  "jq"
  "python3"
  "pip3"
  "mtr"
  "ping"
  "dig"
  "git"
  "wget"
  "netstat"
)

# Install packages if missing
PACKAGES_TO_INSTALL=()

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" &> /dev/null; then
    echo "Tool '$tool' not found, will be installed..."
    case "$tool" in
      "curl") PACKAGES_TO_INSTALL+=("curl") ;;
      "jq") PACKAGES_TO_INSTALL+=("jq") ;;
      "python3") PACKAGES_TO_INSTALL+=("python3") ;;
      "pip3") PACKAGES_TO_INSTALL+=("python3-pip") ;;
      "mtr") PACKAGES_TO_INSTALL+=("mtr") ;;
      "ping") PACKAGES_TO_INSTALL+=("iputils-ping") ;;
      "dig") PACKAGES_TO_INSTALL+=("dnsutils") ;;
      "git") PACKAGES_TO_INSTALL+=("git") ;;
      "wget") PACKAGES_TO_INSTALL+=("wget") ;;
      "netstat") PACKAGES_TO_INSTALL+=("net-tools") ;;
    esac
  fi
done

# Install packages if any are missing
if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
  echo "Installing packages: ${PACKAGES_TO_INSTALL[*]}"
  apt-get install -y "${PACKAGES_TO_INSTALL[@]}"
fi

# Ensure Python packages are installed
if ! python3 -c "import requests" 2>/dev/null; then
  echo "Installing Python packages..."
  pip3 install requests numpy 2>/dev/null || true
fi

echo "=== Setup Complete ==="
