#!/bin/bash
# SSM Agent diagnostic user-data script
# Ensures SSM agent is enabled/started and logs diagnostics to console.
# Used by CI SSM validation test to diagnose registration failures.

# Ensure SSM agent is enabled and started
systemctl enable amazon-ssm-agent 2>/dev/null || true
systemctl start amazon-ssm-agent 2>/dev/null || true

# Log diagnostics to console for debugging
{
  echo "=== SSM Agent Diagnostics ==="
  echo "--- Instance Identity ---"
  TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
  if [ -n "$TOKEN" ]; then
    echo "IMDS: accessible (IMDSv2)"
    curl -sH "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null
    echo ""
    echo "IAM role:"
    curl -sH "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/iam/info 2>/dev/null
    echo ""
  else
    echo "IMDS: NOT accessible via IMDSv2, trying v1..."
    curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null
    echo ""
    curl -s http://169.254.169.254/latest/meta-data/iam/info 2>/dev/null
    echo ""
  fi
  echo "--- SSM Agent Service ---"
  systemctl status amazon-ssm-agent 2>&1 || echo "SSM agent service not found"
  echo "--- SSM Agent Log (last 30 lines) ---"
  tail -30 /var/log/amazon/ssm/amazon-ssm-agent.log 2>/dev/null || \
    echo "No SSM agent log found"
  echo "--- Firewall Status ---"
  firewall-cmd --get-active-zones 2>/dev/null || echo "firewalld not active"
  firewall-cmd --list-all 2>/dev/null || echo "firewalld list-all failed"
  echo "--- Network ---"
  ip route show 2>/dev/null
  echo "--- DNS ---"
  nslookup ssm.us-east-1.amazonaws.com 2>/dev/null || \
    host ssm.us-east-1.amazonaws.com 2>/dev/null || \
    echo "DNS lookup failed"
  echo "=== End SSM Diagnostics ==="
} > /dev/console 2>&1
