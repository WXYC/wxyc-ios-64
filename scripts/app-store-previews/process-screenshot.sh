#!/bin/zsh
#
# process-screenshot.sh
# app-store-previews
#
# Processes screenshots into Apple App Store required formats.
# Handles automatic scaling, cropping, and format conversion.
#
# Created by Jake on 01/23/26.
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_NAME="$(basename "${0}")"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/process-screenshot.log"

# Default output format
DEFAULT_FORMAT="png"
DEFAULT_QUALITY="95"

# ============================================================================
# Device Specifications
# ============================================================================

typeset -A SCREENSHOT_SPECS

# iPhone specs - using the most common/required sizes
# Format: WIDTHxHEIGHT (portrait)
SCREENSHOT_SPECS[iphone-6.9-portrait]="1320x2868"
SCREENSHOT_SPECS[iphone-6.9-landscape]="2868x1320"
SCREENSHOT_SPECS[iphone-6.5-portrait]="1284x2778"
SCREENSHOT_SPECS[iphone-6.5-landscape]="2778x1284"
SCREENSHOT_SPECS[iphone-6.3-portrait]="1206x2622"
SCREENSHOT_SPECS[iphone-6.3-landscape]="2622x1206"
SCREENSHOT_SPECS[iphone-6.1-portrait]="1170x2532"
SCREENSHOT_SPECS[iphone-6.1-landscape]="2532x1170"
SCREENSHOT_SPECS[iphone-5.5-portrait]="1242x2208"
SCREENSHOT_SPECS[iphone-5.5-landscape]="2208x1242"
SCREENSHOT_SPECS[iphone-4.7-portrait]="750x1334"
SCREENSHOT_SPECS[iphone-4.7-landscape]="1334x750"

# iPad specs
SCREENSHOT_SPECS[ipad-13-portrait]="2064x2752"
SCREENSHOT_SPECS[ipad-13-landscape]="2752x2064"
SCREENSHOT_SPECS[ipad-12.9-portrait]="2048x2732"
SCREENSHOT_SPECS[ipad-12.9-landscape]="2732x2048"
SCREENSHOT_SPECS[ipad-11-portrait]="1668x2388"
SCREENSHOT_SPECS[ipad-11-landscape]="2388x1668"
SCREENSHOT_SPECS[ipad-10.5-portrait]="1668x2224"
SCREENSHOT_SPECS[ipad-10.5-landscape]="2224x1668"
SCREENSHOT_SPECS[ipad-9.7-portrait]="1536x2048"
SCREENSHOT_SPECS[ipad-9.7-landscape]="2048x1536"

# Mac specs
SCREENSHOT_SPECS[mac-16x10]="2880x1800"
SCREENSHOT_SPECS[mac-16x10-small]="1440x900"

# Apple TV
SCREENSHOT_SPECS[appletv-4k]="3840x2160"
SCREENSHOT_SPECS[appletv-hd]="1920x1080"

# Apple Vision Pro
SCREENSHOT_SPECS[visionpro]="3840x2160"

# Apple Watch specs
SCREENSHOT_SPECS[watch-ultra3]="422x514"
SCREENSHOT_SPECS[watch-ultra]="410x502"
SCREENSHOT_SPECS[watch-series10]="416x496"
SCREENSHOT_SPECS[watch-series9]="396x484"
SCREENSHOT_SPECS[watch-series6]="368x448"
SCREENSHOT_SPECS[watch-series3]="312x390"

# Required specs for App Store submission
REQUIRED_IPHONE="iphone-6.9"
REQUIRED_IPAD="ipad-13"

# ============================================================================
# Logging
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# ============================================================================
# Helper Functions
# ============================================================================

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] <input-image>

Process screenshots into App Store format.

OPTIONS:
    -d, --device <device>     Target device (see list below)
    -o, --output <path>       Output file path (default: auto-generated)
    -O, --output-dir <dir>    Output directory (default: same as input)
    -a, --all                 Generate all required sizes from input
    -p, --portrait            Force portrait orientation
    -l, --landscape           Force landscape orientation
    -f, --format <fmt>        Output format: png, jpg (default: png)
    -q, --quality <1-100>     JPEG quality (default: 95)
    -s, --scale <mode>        Scale mode: fit, fill, crop (default: fill)
    -b, --background <color>  Background color for letterboxing (default: white)
    --dry-run                 Show what would be done without executing
    -v, --verbose             Verbose output
    -h, --help                Show this help message

DEVICES:
    iPhone (screenshots):
        iphone-6.9      6.9" (iPhone 16 Pro Max, etc.) - REQUIRED
        iphone-6.5      6.5" (iPhone 14 Plus, 13 Pro Max, etc.)
        iphone-6.3      6.3" (iPhone 16 Pro, 15 Pro, etc.)
        iphone-6.1      6.1" (iPhone 16, 14, 13, etc.)
        iphone-5.5      5.5" (iPhone 8 Plus, etc.)
        iphone-4.7      4.7" (iPhone SE, 8, etc.)

    iPad:
        ipad-13         13" (iPad Pro, iPad Air) - REQUIRED
        ipad-12.9       12.9" (iPad Pro 2nd gen)
        ipad-11         11" (iPad Pro, iPad Air, iPad mini)
        ipad-10.5       10.5" (iPad Pro, iPad Air 3rd gen)
        ipad-9.7        9.7" (older iPads)

    Mac:
        mac-16x10       Mac (2880x1800) - REQUIRED
        mac-16x10-small Mac (1440x900)

    Apple TV:
        appletv-4k      Apple TV 4K (3840x2160)
        appletv-hd      Apple TV HD (1920x1080) - REQUIRED

    Apple Vision Pro:
        visionpro       Vision Pro (3840x2160) - REQUIRED

    Apple Watch:
        watch-ultra3    Ultra 3 (422x514) - REQUIRED
        watch-ultra     Ultra 2/Ultra (410x502)
        watch-series10  Series 11/10 (416x496)
        watch-series9   Series 9/8/7 (396x484)
        watch-series6   Series 6/5/4/SE (368x448)
        watch-series3   Series 3 (312x390)

SCALE MODES:
    fill    Scale to fill bounds, crop excess (default - best for screenshots)
    fit     Scale to fit within bounds, add letterbox if needed
    crop    Center crop to exact size without scaling

EXAMPLES:
    # Process for 6.9" iPhone in portrait
    $SCRIPT_NAME -d iphone-6.9 -p screenshot.png

    # Generate all required sizes
    $SCRIPT_NAME -a screenshot.png

    # Process with fill mode and JPEG output
    $SCRIPT_NAME -d ipad-13 -f jpg -q 90 screenshot.png

    # Process Apple Watch screenshot
    $SCRIPT_NAME -d watch-ultra3 watch_screenshot.png

EOF
}

list_devices() {
    echo "Available devices:"
    for device in "${(k)SCREENSHOT_SPECS[@]}"; do
        echo "  $device: ${SCREENSHOT_SPECS[$device]}"
    done | sort
}

detect_orientation() {
    local input="$1"
    local dimensions
    dimensions=$(sips -g pixelWidth -g pixelHeight "$input" 2>/dev/null | tail -2)
    local width height
    width=$(echo "$dimensions" | grep pixelWidth | awk '{print $2}')
    height=$(echo "$dimensions" | grep pixelHeight | awk '{print $2}')

    if [[ $width -gt $height ]]; then
        echo "landscape"
    else
        echo "portrait"
    fi
}

get_image_dimensions() {
    local input="$1"
    local dimensions
    dimensions=$(sips -g pixelWidth -g pixelHeight "$input" 2>/dev/null | tail -2)
    local width height
    width=$(echo "$dimensions" | grep pixelWidth | awk '{print $2}')
    height=$(echo "$dimensions" | grep pixelHeight | awk '{print $2}')
    echo "${width}x${height}"
}

get_output_filename() {
    local input="$1"
    local device="$2"
    local orientation="$3"
    local output_dir="$4"
    local format="$5"

    local basename
    basename=$(basename "$input" | sed 's/\.[^.]*$//')

    echo "${output_dir}/${basename}_${device}_${orientation}.${format}"
}

# ============================================================================
# Image Processing
# ============================================================================

process_image() {
    local input="$1"
    local output="$2"
    local target_resolution="$3"
    local scale_mode="$4"
    local format="$5"
    local quality="$6"
    local background="$7"
    local verbose="$8"
    local dry_run="$9"

    local target_width target_height
    target_width=$(echo "$target_resolution" | cut -d'x' -f1)
    target_height=$(echo "$target_resolution" | cut -d'x' -f2)

    # Get source dimensions
    local src_dims
    src_dims=$(get_image_dimensions "$input")
    local src_width src_height
    src_width=$(echo "$src_dims" | cut -d'x' -f1)
    src_height=$(echo "$src_dims" | cut -d'x' -f2)

    if [[ "$verbose" == "true" ]]; then
        log_info "Source: ${src_width}x${src_height}, Target: ${target_width}x${target_height}"
        log_info "Scale mode: $scale_mode, Format: $format"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would process: $(basename "$input") -> $(basename "$output")"
        log_info "[DRY RUN] Target resolution: ${target_width}x${target_height}"
        return 0
    fi

    log_info "Processing: $(basename "$input") -> $(basename "$output")"

    # Create temporary file for processing
    local tmp_file
    tmp_file=$(mktemp "/tmp/screenshot_XXXXXX.png")
    cp "$input" "$tmp_file"

    case "$scale_mode" in
        fill)
            # Scale to fill, then crop to exact size
            local scale_w scale_h
            local src_aspect target_aspect

            # Calculate aspect ratios (multiply by 1000 for integer math)
            src_aspect=$((src_width * 1000 / src_height))
            target_aspect=$((target_width * 1000 / target_height))

            if [[ $src_aspect -gt $target_aspect ]]; then
                # Source is wider - scale by height, crop width
                scale_h=$target_height
                scale_w=$((src_width * target_height / src_height))
            else
                # Source is taller - scale by width, crop height
                scale_w=$target_width
                scale_h=$((src_height * target_width / src_width))
            fi

            # Scale
            sips --resampleHeight $scale_h "$tmp_file" --out "$tmp_file" >/dev/null 2>&1 || \
            sips --resampleWidth $scale_w "$tmp_file" --out "$tmp_file" >/dev/null 2>&1

            # Crop to exact dimensions
            sips --cropToHeightWidth $target_height $target_width "$tmp_file" --out "$tmp_file" >/dev/null 2>&1
            ;;

        fit)
            # Scale to fit within bounds, add letterbox
            sips --resampleHeightWidthMax $target_height $target_width "$tmp_file" --out "$tmp_file" >/dev/null 2>&1

            # Pad to exact size with background color
            sips --padToHeightWidth $target_height $target_width --padColor "$background" "$tmp_file" --out "$tmp_file" >/dev/null 2>&1
            ;;

        crop)
            # Center crop without scaling
            sips --cropToHeightWidth $target_height $target_width "$tmp_file" --out "$tmp_file" >/dev/null 2>&1
            ;;
    esac

    # Ensure exact dimensions (sips can be off by a pixel sometimes)
    sips --resampleHeightWidth $target_height $target_width "$tmp_file" --out "$tmp_file" >/dev/null 2>&1

    # Convert to output format
    case "$format" in
        jpg|jpeg)
            sips --setProperty format jpeg --setProperty formatOptions "$quality" "$tmp_file" --out "$output" >/dev/null 2>&1
            ;;
        png)
            sips --setProperty format png "$tmp_file" --out "$output" >/dev/null 2>&1
            ;;
    esac

    rm -f "$tmp_file"

    # Verify output
    local out_dims
    out_dims=$(get_image_dimensions "$output")
    log_info "✅ Created: $output ($out_dims)"

    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    local device=""
    local output=""
    local output_dir=""
    local generate_all="false"
    local force_orientation=""
    local format="$DEFAULT_FORMAT"
    local quality="$DEFAULT_QUALITY"
    local scale_mode="fill"
    local background="FFFFFF"
    local dry_run="false"
    local verbose="false"
    local input=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--device)
                device="$2"
                shift 2
                ;;
            -o|--output)
                output="$2"
                shift 2
                ;;
            -O|--output-dir)
                output_dir="$2"
                shift 2
                ;;
            -a|--all)
                generate_all="true"
                shift
                ;;
            -p|--portrait)
                force_orientation="portrait"
                shift
                ;;
            -l|--landscape)
                force_orientation="landscape"
                shift
                ;;
            -f|--format)
                format="$2"
                shift 2
                ;;
            -q|--quality)
                quality="$2"
                shift 2
                ;;
            -s|--scale)
                scale_mode="$2"
                shift 2
                ;;
            -b|--background)
                background="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                input="$1"
                shift
                ;;
        esac
    done

    # Validate input
    if [[ -z "$input" ]]; then
        log_error "No input file specified"
        show_usage
        exit 1
    fi

    if [[ ! -f "$input" ]]; then
        log_error "Input file not found: $input"
        exit 1
    fi

    # Validate format
    case "$format" in
        png|jpg|jpeg) ;;
        *)
            log_error "Unsupported format: $format (use png or jpg)"
            exit 1
            ;;
    esac

    # Set output directory
    if [[ -z "$output_dir" ]]; then
        output_dir=$(dirname "$input")
    fi
    mkdir -p "$output_dir"

    # Detect orientation if not forced
    local orientation
    if [[ -n "$force_orientation" ]]; then
        orientation="$force_orientation"
    else
        orientation=$(detect_orientation "$input")
    fi
    log_info "Detected orientation: $orientation"

    # Log source dimensions
    local src_dims
    src_dims=$(get_image_dimensions "$input")
    log_info "Source dimensions: $src_dims"

    # Process images
    if [[ "$generate_all" == "true" ]]; then
        # Generate all required sizes
        log_info "Generating all required App Store screenshot sizes..."

        local devices_to_process=()

        # iPhone and iPad based on orientation
        if [[ "$orientation" == "portrait" ]]; then
            devices_to_process+=("${REQUIRED_IPHONE}-portrait" "${REQUIRED_IPAD}-portrait")
        else
            devices_to_process+=("${REQUIRED_IPHONE}-landscape" "${REQUIRED_IPAD}-landscape")
        fi

        for target_device in "${devices_to_process[@]}"; do
            local target_res="${SCREENSHOT_SPECS[$target_device]}"
            if [[ -z "$target_res" ]]; then
                log_warn "Skipping unknown device: $target_device"
                continue
            fi
            local device_base
            device_base=$(echo "$target_device" | sed 's/-portrait$//' | sed 's/-landscape$//')
            local out_file
            out_file=$(get_output_filename "$input" "$device_base" "$orientation" "$output_dir" "$format")

            process_image "$input" "$out_file" "$target_res" "$scale_mode" "$format" "$quality" "$background" "$verbose" "$dry_run"
        done
    else
        # Process single device
        if [[ -z "$device" ]]; then
            log_error "No device specified. Use -d <device> or -a for all required sizes."
            show_usage
            exit 1
        fi

        local full_device_key="${device}-${orientation}"

        # Check if device exists (try with and without orientation suffix)
        local target_res=""
        if (( ${+SCREENSHOT_SPECS[$full_device_key]} )); then
            target_res="${SCREENSHOT_SPECS[$full_device_key]}"
        elif (( ${+SCREENSHOT_SPECS[$device]} )); then
            target_res="${SCREENSHOT_SPECS[$device]}"
            full_device_key="$device"
        else
            log_error "Unknown device: $device"
            list_devices
            exit 1
        fi

        # Determine output path
        if [[ -z "$output" ]]; then
            output=$(get_output_filename "$input" "$device" "$orientation" "$output_dir" "$format")
        fi

        process_image "$input" "$output" "$target_res" "$scale_mode" "$format" "$quality" "$background" "$verbose" "$dry_run"
    fi

    log_info "Processing complete!"
}

main "$@"
