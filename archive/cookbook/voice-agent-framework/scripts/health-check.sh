#!/bin/bash
# HVAC Grace Health Check Script

echo "=== HVAC Grace Health Check $(date) ==="

# Check services
echo -e "\n--- Service Status ---"
systemctl is-active hvac-grace-agent && echo "hvac-grace-agent: OK" || echo "hvac-grace-agent: FAILED"

# Check Docker containers
echo -e "\n--- Docker Containers ---"
for container in whisper-server vllm-qwen32b tts-server kokoro-tts; do
  if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
    echo "$container: RUNNING"
  else
    echo "$container: NOT RUNNING"
  fi
done

# Check endpoints
echo -e "\n--- Endpoint Health ---"
curl -s --max-time 5 http://localhost:8000/v1/models > /dev/null && echo "vLLM (8000): OK" || echo "vLLM (8000): FAILED"
curl -s --max-time 5 http://localhost:8001/ > /dev/null && echo "Whisper (8001): OK" || echo "Whisper (8001): FAILED"
curl -s --max-time 5 http://localhost:8002/ > /dev/null && echo "TTS (8002): OK" || echo "TTS (8002): FAILED"

# Check resources
echo -e "\n--- Resources ---"
free -h | grep Mem
df -h / | tail -1
nvidia-smi --query-gpu=temperature.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null || echo "GPU: N/A"

# Check ~/.openclaw directory
echo -e "\n--- OpenClaw Directory ---"
if [ -d "$HOME/.openclaw" ]; then
  echo "~/.openclaw: EXISTS"
  du -sh "$HOME/.openclaw" 2>/dev/null | awk '{print "Size: " $1}'
  
  # Check OpenClaw gateway if running
  if pgrep -f "openclaw" > /dev/null; then
    echo "OpenClaw gateway: RUNNING"
  else
    echo "OpenClaw gateway: NOT RUNNING"
  fi
  
  # Check workspace
  if [ -d "$HOME/.openclaw/workspace" ]; then
    echo "Workspace: EXISTS"
    git -C "$HOME/.openclaw/workspace" status --short 2>/dev/null | wc -l | xargs -I {} echo "Uncommitted changes: {}"
  else
    echo "Workspace: NOT FOUND"
  fi
else
  echo "~/.openclaw: NOT FOUND"
fi

# Check recent errors
echo -e "\n--- Recent Errors (last 5 min) ---"
journalctl -u hvac-grace-agent --since "5 minutes ago" --no-pager 2>/dev/null | grep -iE "error|exception|failed" | tail -5 || echo "No recent errors"

echo -e "\n=== Health Check Complete ==="
