#!/usr/bin/env bash
# wifi-wizard.sh — Interactive WiFi connection wizard for Cubieboard4 A80
set -euo pipefail

SELF="$(basename "$0")"
WIFI_DEV="${WIFI_DEV:-wlan0}"
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
LOGFILE="/tmp/wifi-wizard-$(date -u '+%Y%m%d-%H%M%S').log"

# ── Colors ────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

die()   { printf "\n${RED}✖ ERROR: %s${NC}\n" "$*" >&2; exit 1; }
step()  { printf "\n${CYAN}════════════════════════════════════════════════${NC}\n${BOLD}%s${NC}\n" "$*"; }
info()  { printf "  %s\n" "$*"; }
ok()    { printf "  ${GREEN}✔ %s${NC}\n" "$*"; }
warn()  { printf "  ${YELLOW}⚠ %s${NC}\n" "$*"; }
log()   { printf "[%s] %s\n" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOGFILE"; }

sep()   { printf "  ${CYAN}────────────────────────────────────────────${NC}\n"; }
print_n() { printf "${BOLD}%s${NC}\n" "$*"; }

cleanup() {
	[ -n "${WPA_PID:-}" ] && kill "$WPA_PID" 2>/dev/null || true
}
trap cleanup EXIT

# ── Prerequisites ──────────────────────────────────────────────
check_prereqs() {
	step "Prerequisites"
	local missing=""
	local checks=(
		"iw:iw"
		"wpa_supplicant:wpasupplicant"
		"wpa_passphrase:wpasupplicant"
		"dhclient:isc-dhcp-client"
	)
	for entry in "${checks[@]}"; do
		local cmd="${entry%%:*}"
		local pkg="${entry#*:}"
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing="$missing $pkg"
		fi
	done

	if [ -n "$missing" ]; then
		for pkg in $missing; do echo "  $pkg"; done
		die "Missing packages. Install with: apt-get install $(echo $missing | tr ' ' '\n' | sort -u | tr '\n' ' ')"
	fi
	ok "All required tools found"
}

show_wifi_diagnostics() {
	step "WiFi diagnostics"

	info "Network interfaces:"
	ls -1 /sys/class/net/ 2>/dev/null | while IFS= read -r iface; do
		printf "  %-10s type=%s\n" "$iface" "$(cat "/sys/class/net/$iface/type" 2>/dev/null || echo '?')"
	done

	info ""
	info "AP6330 firmware files:"
	for fw in \
		/lib/firmware/brcm/brcmfmac4330-sdio.bin \
		/lib/firmware/brcm/brcmfmac4330-sdio.txt; do
		if [ -f "$fw" ]; then
			printf "  OK      %s (%s bytes)\n" "$fw" "$(stat -c%s "$fw" 2>/dev/null || echo '?')"
		else
			printf "  MISSING %s\n" "$fw"
		fi
	done

	info ""
	info "Broadcom kernel modules:"
	if grep -E '^(brcmfmac|brcmutil|cfg80211) ' /proc/modules >/dev/null 2>&1; then
		grep -E '^(brcmfmac|brcmutil|cfg80211) ' /proc/modules | while IFS= read -r line; do
			printf "  %s\n" "$line"
		done
	else
		printf "  none loaded\n"
	fi

	info ""
	info "MMC/SDIO devices:"
	if ls /sys/bus/mmc/devices/* >/dev/null 2>&1; then
		for dev in /sys/bus/mmc/devices/*; do
			[ -d "$dev" ] || continue
			printf "  %s" "$(basename "$dev")"
			[ -f "$dev/type" ] && printf " type=%s" "$(cat "$dev/type")"
			[ -f "$dev/name" ] && printf " name=%s" "$(cat "$dev/name")"
			printf "\n"
		done
	else
		printf "  no MMC devices visible in sysfs\n"
	fi

	info ""
	info "Recent kernel messages:"
	dmesg 2>/dev/null | grep -Ei 'brcm|firmware|mmc1|1c10000|sdio|wlan|cfg80211|rfkill' | tail -40 | while IFS= read -r line; do
		printf "  %s\n" "$line"
	done
}

find_wifi_interface() {
	if iw dev "$WIFI_DEV" info >/dev/null 2>&1; then
		return 0
	fi

	WIFI_DEV=""
	for dev in /sys/class/net/wlan*; do
		[ -e "$dev" ] || continue
		if iw dev "$(basename "$dev")" info >/dev/null 2>&1; then
			WIFI_DEV="$(basename "$dev")"
			return 0
		fi
	done

	return 1
}

# ── Detect interface ───────────────────────────────────────────
detect_wifi() {
	step "Detect WiFi interface"
	info "Looking for $WIFI_DEV..."

	if ! find_wifi_interface; then
		if command -v rfkill >/dev/null 2>&1; then
			rfkill unblock wifi 2>/dev/null || true
		fi
		if command -v modprobe >/dev/null 2>&1; then
			info "Loading brcmfmac module..."
			modprobe brcmfmac 2>/dev/null || warn "modprobe brcmfmac failed"
			sleep 2
		fi
	fi

	if ! find_wifi_interface; then
		show_wifi_diagnostics
		die "No WiFi interface found. Check DTB mmc1, AP6330 firmware, and brcmfmac kernel messages above."
	fi

	local RFKILL
	RFKILL=$(rfkill list wifi 2>/dev/null | grep -c "Soft blocked: yes") || true
	if [ "$RFKILL" -gt 0 ]; then
		info "WiFi blocked. Unblocking..."
		rfkill unblock wifi || warn "rfkill unblock failed"
	fi

	# Bring interface up
	ip link set "$WIFI_DEV" up 2>/dev/null || die "Cannot bring $WIFI_DEV up"
	sleep 1
	ok "Interface $WIFI_DEV ready"
}

# ── Scan ───────────────────────────────────────────────────────
scan_networks() {
	step "Scanning networks on $WIFI_DEV..."
	info "Scanning (5 sec) ..."

	local scan_out
	scan_out=$(iw dev "$WIFI_DEV" scan 2>&1) || die "Scan failed: $scan_out"

	# Parse BSSID, SSID, signal, security
	NETWORKS=()
	NET_COUNT=0
	local bssid="" ssid="" signal="" security="" in_bss=0

	while IFS= read -r line; do
		case "$line" in
			BSS\ *)
				# Save previous if we have one
				if [ $in_bss -eq 1 ] && [ -n "$ssid" ]; then
					NETWORKS+=("$bssid|$ssid|$signal|$security")
					NET_COUNT=$((NET_COUNT + 1))
				fi
				bssid="${line#BSS }"; bssid="${bssid%% \(on*}"
				ssid=""; signal=""; security=""; in_bss=1
				;;
			*\ SSID:*)
				ssid="${line#*SSID: }"
				;;
			*\ signal:*)
				signal="${line##*signal: }"; signal="${signal% dBm*}"
				;;
			*\ Capability:*|*\ RSN:*|*\ WPA:*)
				[ -z "$security" ] && security="WPA/WPA2"
				;;
		esac
	done <<< "$scan_out"

	# Last one
	if [ $in_bss -eq 1 ] && [ -n "$ssid" ]; then
		NETWORKS+=("$bssid|$ssid|$signal|$security")
		NET_COUNT=$((NET_COUNT + 1))
	fi

	if [ $NET_COUNT -eq 0 ]; then
		warn "No networks found. Try again later or check antenna."
		return 1
	fi

	# Sort by signal strength (best first) using numeric sort on field 3
	local sorted
	sorted=$(printf '%s\n' "${NETWORKS[@]}" | sort -t'|' -k3 -rn) || true
	NETWORKS_SORTED=()
	NET_COUNT=0
	while IFS= read -r line; do
		[ -z "$line" ] && continue
		NETWORKS_SORTED+=("$line")
		NET_COUNT=$((NET_COUNT + 1))
	done <<< "$sorted"

	ok "Found $NET_COUNT networks"
	return 0
}

# ── Display and select ─────────────────────────────────────────
select_network() {
	step "Select WiFi network"

	printf "  ${BOLD}%-3s %-30s %-8s %s${NC}\n" "#" "SSID" "Signal" "Security"
	sep
	local i=0
	for entry in "${NETWORKS_SORTED[@]}"; do
		i=$((i + 1))
		local IFS='|'
		read -r bssid ssid signal security <<< "$entry"
		# Strip hidden SSIDs
		[ -z "$ssid" ] && ssid="(hidden)"
		printf "  %-3d %-30s %-+4s dBm  %s\n" "$i" "$ssid" "$signal" "$security"
	done
	sep

	local choice
	printf "\n  Enter network number (1-%d), 'm' for manual SSID, 'r' to rescan: " "$NET_COUNT"
	read -r choice </dev/tty

	case "$choice" in
		[rR]) scan_networks && select_network; return ;;
		[mM]) manual_ssid; return ;;
		*)
			if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$NET_COUNT" ]; then
				selected_idx=$((choice - 1))
				local IFS='|'
				read -r SELECTED_BSSID SELECTED_SSID SELECTED_SIGNAL SELECTED_SECURITY <<< "${NETWORKS_SORTED[$selected_idx]}"
				[ -z "$SELECTED_SSID" ] && die "Cannot connect to hidden SSID. Use manual entry."
				ok "Selected: $SELECTED_SSID ($SELECTED_SIGNAL dBm)"
			else
				info "Invalid choice"
				select_network
				return
			fi
			;;
	esac
}

manual_ssid() {
	printf "\n  ${BOLD}Enter SSID manually:${NC} "
	read -r SELECTED_SSID </dev/tty
	[ -z "$SELECTED_SSID" ] && die "SSID cannot be empty"
	SELECTED_BSSID=""
	ok "Manual SSID: $SELECTED_SSID"
}

# ── Password ───────────────────────────────────────────────────
get_password() {
	step "Authentication"

	printf "  Network: ${BOLD}%s${NC}\n" "$SELECTED_SSID"
	printf "\n  Enter passphrase (WPA/WPA2): "
	read -r -s WIFI_PASS </dev/tty
	printf "\n"
	[ -z "$WIFI_PASS" ] && die "Passphrase cannot be empty"

	local confirm
	printf "  Confirm passphrase: "
	read -r -s confirm </dev/tty
	printf "\n"
	[ "$WIFI_PASS" != "$confirm" ] && die "Passphrases do not match"

	# Generate PSK and show hash
	{
		wpa_passphrase "$SELECTED_SSID" "$WIFI_PASS"
	} > /dev/null 2>&1 || die "Failed to generate PSK"
	ok "Passphrase accepted"
}

# ── Connect ────────────────────────────────────────────────────
do_connect() {
	step "Connecting to $SELECTED_SSID"

	# Kill any existing wpa_supplicant on this interface
	wpa_cli -i "$WIFI_DEV" terminate 2>/dev/null || true
	sleep 1

	local psk
	psk=$(wpa_passphrase "$SELECTED_SSID" "$WIFI_PASS" | awk -F= '/^\tpsk=/ {print $2}')

	# Create a temporary config
	local WPA_CONF_TMP="/tmp/wpa_supplicant_$WIFI_DEV.conf"
	cat > "$WPA_CONF_TMP" <<-EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
	ssid="$SELECTED_SSID"
	psk=$psk
	key_mgmt=WPA-PSK
EOF
	[ -n "$SELECTED_BSSID" ] && printf '\tbssid=%s\n' "$SELECTED_BSSID" >> "$WPA_CONF_TMP"
	printf '}\n' >> "$WPA_CONF_TMP"

	# Start wpa_supplicant
	info "Starting wpa_supplicant..."
	wpa_supplicant -B -i "$WIFI_DEV" -c "$WPA_CONF_TMP" >/dev/null 2>&1 || die "wpa_supplicant failed to start"
	WPA_PID=$(cat /var/run/wpa_supplicant/"$WIFI_DEV" 2>/dev/null) || true

	# Wait for association
	info "Waiting for association..."
	local i
	for i in $(seq 1 15); do
		state=$(wpa_cli -i "$WIFI_DEV" status 2>/dev/null | grep 'wpa_state=' | cut -d= -f2) || state=""
		case "$state" in
			COMPLETED) ok "Associated"; break ;;
			*) sleep 1 ;;
		esac
	done

	if [ "$state" != "COMPLETED" ]; then
		wpa_cli -i "$WIFI_DEV" status 2>/dev/null | grep 'wpa_state=' || true
		die "Failed to associate with $SELECTED_SSID in 15 seconds"
	fi

	# Get IP via dhclient
	info "Requesting IP address (dhclient)..."
	dhclient "$WIFI_DEV" 2>&1 | while IFS= read -r line; do log "dhclient: $line"; done || true

	# Give it a moment
	sleep 2

	local ip
	ip=$(ip -4 addr show "$WIFI_DEV" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1) || true
	if [ -z "$ip" ]; then
		warn "dhclient did not get an IP. Trying dhcpcd..."
		dhcpcd "$WIFI_DEV" 2>/dev/null || true
		sleep 2
		ip=$(ip -4 addr show "$WIFI_DEV" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1) || true
	fi

	if [ -n "$ip" ]; then
		ok "IP address: $ip"
	else
		warn "No IP address obtained. Run 'dhclient $WIFI_DEV' or 'dhcpcd $WIFI_DEV' manually."
		return 1
	fi

	sep
	printf "  ${GREEN}✔${NC} Connected to ${BOLD}%s${NC}\n" "$SELECTED_SSID"
	printf "  ${GREEN}✔${NC} IP: ${BOLD}%s${NC}\n" "$ip"
	printf "  ${GREEN}✔${NC} Interface: ${BOLD}%s${NC}\n" "$WIFI_DEV"

	# Test connectivity
	if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
		ok "Internet reachable"
	else
		warn "Internet not reachable, but link is up (DNS may not work yet)"
	fi
}

# ── Persist ────────────────────────────────────────────────────
persist_config() {
	step "Save configuration"

	printf "\n  Save WiFi config to ${BOLD}%s${NC} for auto-connect on boot?\n" "$WPA_CONF"
	printf "  [Y/n] "
	read -r reply </dev/tty
	case "$reply" in [nN]*) info "Skipped"; return ;; esac

	local dir
	dir=$(dirname "$WPA_CONF")
	[ -d "$dir" ] || mkdir -p "$dir"

	{
		printf 'ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev\n'
		printf 'update_config=1\n'
		printf 'country=US\n\n'
		wpa_passphrase "$SELECTED_SSID" "$WIFI_PASS"
	} > "$WPA_CONF"

	# Ensure wpa_supplicant service is enabled and configured for this interface
	local ns
	ns="/etc/wpa_supplicant/wpa_supplicant-$WIFI_DEV.conf"
	cp "$WPA_CONF" "$ns"

	if command -v systemctl >/dev/null 2>&1; then
		info "To enable auto-connect on boot:"
		info "  systemctl enable wpa_supplicant@$WIFI_DEV"
		info "  systemctl start wpa_supplicant@$WIFI_DEV"
		info "Or add to /etc/network/interfaces:"
		info "  allow-hotplug $WIFI_DEV"
		info "  iface $WIFI_DEV inet dhcp"
		info "      wpa-conf $ns"
	else
		warn "No systemd found. Add 'wpa_supplicant -B -i $WIFI_DEV -c $WPA_CONF' to /etc/rc.local"
	fi

	ok "WiFi config saved to $ns (and $WPA_CONF)"
}

# ── Show connection info ──────────────────────────────────────
show_info() {
	step "Connection info"

	info "SSID:       $SELECTED_SSID"
	info "Interface:  $WIFI_DEV"

	local ip gateway dns
	ip=$(ip -4 addr show "$WIFI_DEV" 2>/dev/null | grep 'inet ' | awk '{print $2}')
	gateway=$(ip route show default 2>/dev/null | awk '{print $3}')
	dns=$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')

	info "IP:         ${ip:-N/A}"
	info "Gateway:    ${gateway:-N/A}"
	info "DNS:        ${dns:-N/A}"

	sep
	iw dev "$WIFI_DEV" link 2>/dev/null | while IFS= read -r line; do
		printf "  %s\n" "$line"
	done
}

# ── Main ───────────────────────────────────────────────────────
main() {
	printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
	printf "${BOLD}  Cubieboard4 — WiFi Wizard${NC}\n"
	printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
	info "Log: $LOGFILE"
	info ""

	check_prereqs
	detect_wifi

	if ! scan_networks; then
		printf "\n  ${YELLOW}⚠ No networks found.${NC}\n"
		printf "  Enter SSID manually? [y/N] "
		read -r reply </dev/tty
		case "$reply" in [yY]*) manual_ssid ;; *) exit 0 ;; esac
	fi

	[ $NET_COUNT -gt 0 ] && select_network
	get_password
	do_connect

	printf "\n"
	persist_config

	printf "\n"
	show_info

	printf "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
	printf "${GREEN}  WiFi setup complete${NC}\n"
	printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

main "$@"
