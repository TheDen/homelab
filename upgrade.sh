#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null 2>&1
  while [ -L "${BASH_SOURCE[0]}" ]; do
    cd -- "$(dirname -- "$(readlink -- "${BASH_SOURCE[0]}")")" > /dev/null 2>&1
  done
  pwd -P
)"

# Service definitions
# Format:
#   name|relative_dir|compose_file|image1,image2,image3
SERVICES=(
  "flame|flame|docker-compose.yaml|pawelmalak/flame:latest"
  "plex|plex|docker-compose.yaml|plexinc/pms-docker:latest"
  "home-assistant|home-assistant|docker-compose.yaml|ghcr.io/home-assistant/home-assistant:stable,ghcr.io/home-assistant-libs/python-matter-server:stable"
  "homebridge|homebridge|docker-compose.yaml|homebridge/homebridge:latest"
  "speedtest-tracker|speedtest-tracker|docker-compose.yaml|lscr.io/linuxserver/speedtest-tracker:latest"
  "uptime-kuma|uptime-kuma|docker-compose.yaml|louislam/uptime-kuma:1"
  "zigbee2mqtt|zigbee2mqtt|docker-compose.yaml|ghcr.io/koenkk/zigbee2mqtt,eclipse-mosquitto:2"
)

get_image_id() {
  local image="$1"
  docker image inspect --format '{{.Id}}' "$image" 2> /dev/null || true
}

update_one_service() {
  local name="$1"
  local rel_dir="$2"
  local compose_file="$3"
  local images_csv="$4"

  local dir="$SCRIPT_DIR/$rel_dir"
  local compose_path="$dir/$compose_file"

  if [[ ! -d "$dir" ]]; then
    echo "Skipping $name: missing dir: $dir" >&2
    return 0
  fi
  if [[ ! -f "$compose_path" ]]; then
    echo "Skipping $name: missing compose file: $compose_path" >&2
    return 0
  fi

  echo
  echo "==> $name"
  echo "    dir:     $rel_dir"
  echo "    compose: $compose_file"

  local needs_restart=false

  IFS=',' read -r -a images <<< "$images_csv"
  for image in "${images[@]}"; do
    image="$(echo "$image" | xargs)" # trim
    [[ -z "$image" ]] && continue

    echo "Checking image: $image"

    local current_id new_id
    current_id="$(get_image_id "$image")"

    docker pull "$image" > /dev/null

    new_id="$(get_image_id "$image")"
    if [[ -z "$new_id" ]]; then
      echo "Error: could not determine image ID for $image after pull" >&2
      return 1
    fi

    if [[ "$current_id" != "$new_id" ]]; then
      echo "New image detected: $image"
      needs_restart=true
    else
      echo "Image unchanged: $image"
    fi
  done

  if [[ "$needs_restart" == true ]]; then
    echo "Restarting $name..."
    (
      cd "$dir"
      docker compose -f "$compose_file" up -d --no-deps --force-recreate
    )
  else
    echo "$name is up to date. No restart needed."
  fi
}

system_reboot_required() {
  if [[ -f /var/run/reboot-required ]]; then
    return 0
  fi

  if command -v needsrestart > /dev/null 2>&1; then
    # needsrestart -r returns: 0 = no restart needed, 1 = services, 2 = reboot required (common)
    if needsrestart -r > /dev/null 2>&1; then
      return 1
    else
      # If it exits non-zero, we can't reliably infer; fall back to "not required"
      return 1
    fi
  fi

  return 1
}

echo "Updating system packages..."
sudo apt update -y
sudo apt upgrade -y
sudo apt dist-upgrade -y

failures=0
for entry in "${SERVICES[@]}"; do
  IFS='|' read -r name rel_dir compose_file images_csv <<< "$entry"
  if ! update_one_service "$name" "$rel_dir" "$compose_file" "$images_csv"; then
    echo "Failed: $name" >&2
    failures=$((failures + 1))
  fi
done

echo
if [[ "$failures" -gt 0 ]]; then
  echo "Done with $failures failure(s)." >&2
else
  echo "Done. All services checked."
fi

if [[ -f /var/run/reboot-required ]]; then
  echo
  echo "System restart required: yes"
  echo "Reason(s):"
  cat /var/run/reboot-required 2> /dev/null || true
  if [[ -f /var/run/reboot-required.pkgs ]]; then
    echo
    echo "Packages triggering restart:"
    cat /var/run/reboot-required.pkgs 2> /dev/null || true
  fi
else
  echo
  echo "System restart required: no"
  echo "Running cleanup: apt clean; apt autoclean; apt autoremove"
  sudo apt clean
  sudo apt autoclean
  sudo apt autoremove -y
fi

# Exit non-zero if any service update failed
[[ "$failures" -gt 0 ]] && exit 1 || exit 0
