#!/bin/bash
#
# Configuration file generation functions
#

# Extract VME section from base.cnf
extract_vme_section() {
    local base_file="$1"
    local output_file="$2"

    # Extract everything from start until the VTP Configuration header
    sed -n '1,/^######## VTP Configuration/p' "$base_file" | sed '$d' > "$output_file"
}

# Extract VTP section from base.cnf (excluding MAC/IP table at end)
extract_vtp_section() {
    local base_file="$1"
    local output_file="$2"

    # Extract from VTP Configuration header until the MAC/IP table comment
    sed -n '/^######## VTP Configuration/,/^# VTP rocs, their MAC and IP addresses/p' "$base_file" | sed '$d' > "$output_file"
}

# Get MAC and IP for a hostname from base.cnf
get_mac_ip_from_base() {
    local base_file="$1"
    local hostname="$2"
    local mac_var="$3"  # Variable name to store MAC
    local ip_var="$4"   # Variable name to store IP

    # Find the line for this hostname in the MAC/IP table
    local line=$(grep "^${hostname}[[:space:]]" "$base_file")

    if [[ -z "$line" ]]; then
        echo "WARNING: No MAC/IP mapping found for hostname: $hostname in $base_file"
        eval $mac_var=""
        eval $ip_var=""
        return 1
    fi

    # Extract MAC (between first set of quotes) and IP (between second set of quotes)
    local mac=$(echo "$line" | sed 's/[^"]*"\([^"]*\)".*/\1/')
    local ip=$(echo "$line" | sed 's/.*"[^"]*"[[:space:]]*"\([^"]*\)".*/\1/')

    # MAC and IP are already in the correct format in base.cnf
    eval $mac_var="'$mac'"
    eval $ip_var="'$ip'"
    return 0
}

# Extract slot numbers from hostname.peds file
extract_slots_from_peds() {
    local peds_file="$1"
    local slots_var="$2"  # Variable name to store array of slots

    if [[ ! -f "$peds_file" ]]; then
        echo "WARNING: Pedestal file not found: $peds_file"
        eval $slots_var="()"
        return 1
    fi

    # Extract all FADC250_SLOT lines and get the slot numbers
    local slot_numbers=$(grep "^FADC250_SLOT" "$peds_file" | awk '{print $2}')

    # Convert to array
    local -a slots_array=($slot_numbers)

    # Return via eval
    eval $slots_var="(${slots_array[@]})"
    return 0
}

# Compute VTP_PAYLOAD_EN from slot numbers
# Slot-to-payload mapping:
#   slot:    10 13  9 14  8 15  7 16  6 17  5 18  4 19  3 20
#   payload:  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16
compute_vtp_payload_en() {
    local -a slots=("$@")

    # Initialize all payloads to 0
    local -a payload_en=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)

    # Map slot to payload index using case statement
    map_slot_to_payload() {
        local slot=$1
        case "$slot" in
            10) echo 0 ;;
            13) echo 1 ;;
            9)  echo 2 ;;
            14) echo 3 ;;
            8)  echo 4 ;;
            15) echo 5 ;;
            7)  echo 6 ;;
            16) echo 7 ;;
            6)  echo 8 ;;
            17) echo 9 ;;
            5)  echo 10 ;;
            18) echo 11 ;;
            4)  echo 12 ;;
            19) echo 13 ;;
            3)  echo 14 ;;
            20) echo 15 ;;
            *)  echo -1 ;;
        esac
    }

    # Set payload bits for present slots
    for slot in "${slots[@]}"; do
        local payload_idx=$(map_slot_to_payload "$slot")
        if [[ $payload_idx -ge 0 ]]; then
            payload_en[$payload_idx]=1
        fi
    done

    # Return as space-separated string
    echo "${payload_en[@]}"
}

# Generate vme_hostname.cnf
generate_vme_config() {
    local hostname="$1"
    local base_file="$2"
    local peds_file="$3"
    local output_dir="$4"

    local output_file="${output_dir}/vme_${hostname}.cnf"

    echo "  Generating: $output_file"

    # Extract VME section from base.cnf
    extract_vme_section "$base_file" "$output_file"

    # Append the pedestal file content to the END of the file
    if [[ -f "$peds_file" ]]; then
        echo "" >> "$output_file"
        cat "$peds_file" >> "$output_file"
        echo "" >> "$output_file"
        echo "  Appended pedestals from: $peds_file ($(wc -l < "$peds_file") lines)"
    else
        echo "WARNING: Pedestal file not found: $peds_file"
    fi
}

# Generate vtp_hostname.cnf
generate_vtp_config() {
    local hostname="$1"
    local base_file="$2"
    local peds_file="$3"
    local output_dir="$4"

    local output_file="${output_dir}/vtp_${hostname}.cnf"

    echo "  Generating: $output_file"

    # Extract VTP section from base.cnf
    extract_vtp_section "$base_file" "$output_file"

    # Get MAC and IP from base.cnf
    local mac_addr=""
    local ip_addr=""
    get_mac_ip_from_base "$base_file" "$hostname" mac_addr ip_addr

    # Extract slots from peds file
    local -a slots=()
    extract_slots_from_peds "$peds_file" slots

    # Compute VTP_PAYLOAD_EN
    local payload_en=$(compute_vtp_payload_en "${slots[@]}")

    # Append VTP_PAYLOAD_EN
    cat >> "$output_file" <<EOF

#        slot: 10 13  9 14  8 15  7 16  6 17  5 18  4 19  3 20
#     payload:  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16
VTP_PAYLOAD_EN  $payload_en

VTP_STREAMING_ROCID       0
VTP_STREAMING_NFRAME_BUF  1000
VTP_STREAMING_FRAMELEN    65536

###################################################
#VTP FADC Streaming event builder #0 (slots 3-10) #
###################################################
VTP_STREAMING             0

VTP_STREAMING_MAC         $mac_addr

VTP_STREAMING_NSTREAMS    1

VTP_STREAMING_IPADDR      $ip_addr
VTP_STREAMING_SUBNET      255 255 255   0
VTP_STREAMING_GATEWAY     129  57 69   1

VTP_STREAMING_DESTIP      129.57.177.3
VTP_STREAMING_DESTIPPORT  19522
VTP_STREAMING_LOCALPORT   10001

VTP_STREAMING_CONNECT     1

EOF
}
