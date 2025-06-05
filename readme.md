## linux-vm-diagnostics
Bash script to pull diagnostic information from Linux VMs for troubleshooting and compress for sharing - optionally uploads to workspace with `azcopy`. Made for scenarios where sosreport is not available.

### Usage 

```
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/jameswylde/get-linux-logs/main/get-logs.sh)"
```

Collects:
- system info & Azure metadata (if relevant)
- /var/log & /var/lib/waagent

Optionally uses 'azcopy' to upload logs to Azure storage account with SASURI.