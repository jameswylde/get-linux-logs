
#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

log()  { printf '\e[96m%s\e[0m\n' "$*"; }
warn() { printf '\e[33m%s\e[0m\n' "$*"; }
fail() { printf '\e[31m%s - exiting\e[0m\n' "$*"; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run as root ..."
log ""
log " Starting ..."

# ─────────  estimate archive size and confirmation

sources=(/var/log /var/lib/waagent)
archive_size() {
  local bytes
  bytes=$(tar -czf - "${sources[@]}" 2>/dev/null | wc -c)
  numfmt --to=iec --suffix=B --format="%.1f" "$bytes"
}

echo
warn " Estimated log archive size: $(archive_size)"
echo
read -rp $'\e[32m     Continue? [y/n] \e[0m' reply
echo
if [[ ! $reply =~ ^[Yy]$ ]]; then
  log " Terminating ..."
  exit 0
fi

copy_path() {
  local src=$1 dest=$2
  if [[ -e $src ]]; then
    cp -a --parents "$src" "$dest" 2>/dev/null || warn "Could not copy $src ..."
  else
    warn " $src not found ..."
    log ""
  fi
}

ts=$(date '+%Y-%m-%d%_H%M%S')
host=$(hostname)
tz=$(date '+%Z')
diag_dir="$host-${ts}"
mkdir -p "$diag_dir"


# ───────── grab /var/logs/ and /var/lib/waagent
log " [1/3] Zipping log directories ..."
echo
copy_path /var/log "$diag_dir"
copy_path /var/lib/waagent "$diag_dir"


# ───────── grab system information & restarts
log " [2/3] Gathering system information ..."
echo
{
  cat /etc/*-release
  echo
  uname -a
  echo
  df -hT
  echo
  ps -eo pid,ppid,user,pcpu,pmem,args --sort=-pcpu | head -n 50
} > "$diag_dir/system.txt"

#if command -v journalctl &>/dev/null; then
#  journalctl --no-pager --list-boots | head -n 20
#else
#  last -x | grep -E '^(shutdown|reboot|system boot)' | head -n 20
#fi > "$diag_dir/restarts.txt"

journalctl --no-pager --list-boots | head -n 50 "$diag_dir/restarts.txt" && echo "" >> "$diag_dir/restarts.txt"
last -x | grep -E '^(shutdown|reboot|system boot)' | head -n 20 >> "$diag_dir/restarts.txt"

# ───────── grab Azure metadata
if command -v curl &>/dev/null; then
  if ! curl -sf --connect-timeout 2 \
        -H "Metadata: true" \
        "http://169.254.169.254/metadata/instance?api-version=2021-02-01" \
        -o "$diag_dir/azure-metadata.json"; then
    rm -f "$diag_dir/azure-metadata.json"
  fi
fi


# ───────── archive & cleanup
archive="$host-${ts}.tar.gz"
tar -czf "$archive" "$diag_dir"
rm -rf "$diag_dir"
log " [3/3] Archive created → $(pwd)/$archive"
echo


# ───────── optional azcopy upload
if command -v azcopy &>/dev/null; then
  read -rp $'\e[32m     Upload the archive with azcopy [y/n]? \e[0m' choice
  if [[ $choice =~ ^[Yy]$ ]]; then
    read -rp $'\e[32m     Enter SAS URI: \e[0m' sas_uri
    echo
    azcopy copy "$archive" "$sas_uri" 2>&1 #| awk '/^Final Job Status:/ {print; exit}'
    echo
  fi
else
  warn " azcopy not found - skipping ..."
  echo
fi