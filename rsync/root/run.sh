#!/usr/bin/env bashio
# shellcheck shell=bash
set -e

HA_API_URL="http://supervisor/core/api"

publish_sensor() {
  local entity_id="$1"
  local state="$2"
  local attributes="$3"
  local payload

  payload=$(jq -cn --arg state "$state" --argjson attributes "$attributes" \
    '{state: $state, attributes: $attributes}')
  if ! curl --silent --show-error --fail \
    --header "Authorization: Bearer $SUPERVISOR_TOKEN" \
    --header 'Content-Type: application/json' \
    --data "$payload" \
    "${HA_API_URL}/states/${entity_id}" >/dev/null; then
    bashio::log.warning "Unable to publish Home Assistant sensor ${entity_id}"
    return 1
  fi
}

publish_status() {
  local state="$1"
  local start="$2"
  local end="$3"
  local attributes

  attributes=$(jq -cn --arg start "$start" --arg end "$end" \
    '{friendly_name: "Rsync Status", icon: "mdi:sync", last_run_start: $start, last_run_end: $end}')
  publish_sensor sensor.rsync_status "$state" "$attributes" || true
}

publish_progress() {
  local bytes="$1"
  local rate_up="$2"
  local rate_down="$3"

  publish_sensor sensor.rsync_bytes_transferred "$bytes" \
    '{"friendly_name":"Rsync Bytes Transferred","unit_of_measurement":"B","state_class":"measurement","icon":"mdi:database"}' || true
  publish_sensor sensor.rsync_transfer_rate_up "$rate_up" \
    '{"friendly_name":"Rsync Transfer Rate Up","unit_of_measurement":"B/s","state_class":"measurement","icon":"mdi:upload"}' || true
  publish_sensor sensor.rsync_transfer_rate_down "$rate_down" \
    '{"friendly_name":"Rsync Transfer Rate Down","unit_of_measurement":"B/s","state_class":"measurement","icon":"mdi:download"}' || true
}

publish_last_run() {
  local exit_code="$1"
  local duration="$2"

  publish_sensor sensor.rsync_last_exit_code "$exit_code" \
    '{"friendly_name":"Rsync Last Exit Code","icon":"mdi:exit-run"}' || true
  publish_sensor sensor.rsync_last_run_duration "$duration" \
    '{"friendly_name":"Rsync Last Run Duration","unit_of_measurement":"s","state_class":"measurement","icon":"mdi:timer-outline"}' || true
}

process_rsync_output() {
  local direction="$1"
  local completed_bytes="$2"
  local bytes_file="$3"
  local line current_bytes rate_value rate_unit multiplier transfer_rate rate_up rate_down now
  local last_update=0

  while IFS= read -r -d $'\r' line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    printf '%s\n' "$line"

    if [[ "$line" =~ ^[[:space:]]*([0-9,]+)[[:space:]]+[0-9]+%[[:space:]]+([0-9]+([.][0-9]+)?)([kMGT]?B)/s ]]; then
      current_bytes="${BASH_REMATCH[1]//,/}"
      rate_value="${BASH_REMATCH[2]}"
      rate_unit="${BASH_REMATCH[4]}"
      case "$rate_unit" in
        kB) multiplier=1024 ;;
        MB) multiplier=1048576 ;;
        GB) multiplier=1073741824 ;;
        TB) multiplier=1099511627776 ;;
        *) multiplier=1 ;;
      esac
      transfer_rate=$(awk -v rate="$rate_value" -v factor="$multiplier" \
        'BEGIN { printf "%.0f", rate * factor }')
      printf '%s\n' "$current_bytes" > "$bytes_file"

      rate_up=0
      rate_down=0
      if [[ "$direction" == "pull" ]]; then
        rate_down="$transfer_rate"
      else
        rate_up="$transfer_rate"
      fi

      now=$(date +%s)
      if (( now != last_update )); then
        publish_progress "$((completed_bytes + current_bytes))" "$rate_up" "$rate_down"
        last_update="$now"
      fi
    fi
  done
}

run_rsync() {
  local direction="$1"
  local source="$2"
  local target="$3"
  local completed_bytes="$4"
  local output_dir output_fifo bytes_file output_pid rsync_status

  output_dir=$(mktemp -d)
  output_fifo="${output_dir}/output"
  bytes_file="${output_dir}/bytes"
  mkfifo "$output_fifo"
  process_rsync_output "$direction" "$completed_bytes" "$bytes_file" < "$output_fifo" &
  output_pid=$!

  if rsync "${rsync_opts[@]}" --info=progress2 --stats \
    -e "ssh ${SSH_OPTS}" "$source" "$target" > "$output_fifo" 2>&1; then
    rsync_status=0
  else
    rsync_status=$?
  fi

  wait "$output_pid" || true
  LAST_FOLDER_BYTES=0
  if [ -f "$bytes_file" ]; then
    LAST_FOLDER_BYTES=$(cat "$bytes_file")
  fi
  rm -rf "$output_dir"
  return "$rsync_status"
}

PRIVATE_KEY_FILE=$(bashio::config 'private_key_file')
if [ ! -f "$PRIVATE_KEY_FILE" ]; then
  bashio::log.info 'Generate keypair'

  mkdir -p "$(dirname "$PRIVATE_KEY_FILE")"
  ssh-keygen -t ed25519 -f "$PRIVATE_KEY_FILE" -N ''

  bashio::log.info "Generated key-pair in $PRIVATE_KEY_FILE"
else
  bashio::log.info "Use private key from $PRIVATE_KEY_FILE"
fi

HOST=$(bashio::config 'remote_host')
USERNAME=$(bashio::config 'username')
FOLDERS=$(bashio::addon.config | jq -r ".folders")

# Create local directories if they don't exist
echo "$FOLDERS" | jq -c '.[]' | while read -r folder; do
  LOCAL_DIR=$(echo "$folder" | jq -r '.local')
  bashio::log.info "Checking local directory: $LOCAL_DIR"
  if [ ! -d "$LOCAL_DIR" ]; then
    bashio::log.info "Creating local directory: $LOCAL_DIR"
    mkdir -p "$LOCAL_DIR"
  fi
done

if bashio::config.has_value 'remote_port'; then
  PORT=$(bashio::config 'remote_port')
  bashio::log.info "Use port $PORT"
else
  PORT=22
fi

SSH_OPTS="-p ${PORT} -i ${PRIVATE_KEY_FILE} -oStrictHostKeyChecking=accept-new -oPasswordAuthentication=no -oBatchMode=yes -oConnectTimeout=30"

folder_count=$(echo "$FOLDERS" | jq -r '. | length')
sync_errors=0
completed_bytes=0
run_start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
run_start_epoch=$(date +%s)
publish_status running "$run_start" ""
publish_progress 0 0 0

for (( i=0; i<folder_count; i=i+1 )); do

  local_path=$(echo "$FOLDERS" | jq -r ".[$i].local")
  remote=$(echo "$FOLDERS" | jq -r ".[$i].remote")
  options=$(echo "$FOLDERS" | jq -r ".[$i].options // \"--archive --recursive --compress --delete --prune-empty-dirs\"")
  direction=$(echo "$FOLDERS" | jq -r ".[$i].direction // \"push\"")

  # Split options string into array to prevent shell injection via unquoted expansion
  read -ra rsync_opts <<< "${options}"

  if [ "$direction" = "pull" ]; then
    # Pull from remote to local.
    source="${USERNAME}@${HOST}:${remote}"
    target="$local_path"
    bashio::log.info "Sync ${source} -> ${target} with options \"${options}\""
  else
    # Default push from local to remote
    source="$local_path"
    target="${USERNAME}@${HOST}:${remote}"
    bashio::log.info "Sync ${source} -> ${target} with options \"${options}\""
  fi

  if run_rsync "$direction" "$source" "$target" "$completed_bytes"; then
    completed_bytes=$((completed_bytes + LAST_FOLDER_BYTES))
  else
    bashio::log.error "Sync failed: ${source} -> ${target}"
    completed_bytes=$((completed_bytes + LAST_FOLDER_BYTES))
    sync_errors=$((sync_errors + 1))
  fi
done

run_end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
run_duration=$(( $(date +%s) - run_start_epoch ))
publish_progress "$completed_bytes" 0 0

if [ "$sync_errors" -gt 0 ]; then
  bashio::log.warning "Sync completed with ${sync_errors} error(s)"
  publish_status error "$run_start" "$run_end"
  publish_last_run 1 "$run_duration"
  exit 1
fi

bashio::log.info "Synced all folders"
publish_status idle "$run_start" "$run_end"
publish_last_run 0 "$run_duration"
