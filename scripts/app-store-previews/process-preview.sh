#!/bin/zsh
#
# process-preview.sh
# app-store-previews
#
# Processes screen recordings into Apple App Store preview video formats.
# Handles automatic scaling, codec conversion, and format compliance.
#
# Created by Jake on 01/22/26.
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_NAME="$(basename "${0}")"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/process-preview.log"

# Video encoding settings (Apple requirements)
VIDEO_CODEC="libx264"
VIDEO_PROFILE="high"
VIDEO_LEVEL="4.0"
VIDEO_BITRATE="10M"
MAX_BITRATE="12M"
AUDIO_CODEC="aac"
AUDIO_BITRATE="256k"
AUDIO_SAMPLE_RATE="48000"
MAX_FPS="30"
PIXEL_FORMAT="yuv420p"

# ============================================================================
# Device Specifications
# ============================================================================

typeset -A DEVICE_SPECS
# iPhone specs (portrait x landscape)
DEVICE_SPECS[iphone-6.9-portrait]="886x1920"
DEVICE_SPECS[iphone-6.9-landscape]="1920x886"
DEVICE_SPECS[iphone-6.5-portrait]="886x1920"
DEVICE_SPECS[iphone-6.5-landscape]="1920x886"
DEVICE_SPECS[iphone-6.3-portrait]="886x1920"
DEVICE_SPECS[iphone-6.3-landscape]="1920x886"
DEVICE_SPECS[iphone-6.1-portrait]="886x1920"
DEVICE_SPECS[iphone-6.1-landscape]="1920x886"
DEVICE_SPECS[iphone-5.5-portrait]="1080x1920"
DEVICE_SPECS[iphone-5.5-landscape]="1920x1080"
DEVICE_SPECS[iphone-4.7-portrait]="750x1334"
DEVICE_SPECS[iphone-4.7-landscape]="1334x750"
# iPad specs
DEVICE_SPECS[ipad-13-portrait]="1200x1600"
DEVICE_SPECS[ipad-13-landscape]="1600x1200"
DEVICE_SPECS[ipad-11-portrait]="1200x1600"
DEVICE_SPECS[ipad-11-landscape]="1600x1200"
DEVICE_SPECS[ipad-10.5-portrait]="1200x1600"
DEVICE_SPECS[ipad-10.5-landscape]="1600x1200"
DEVICE_SPECS[ipad-9.7-portrait]="900x1200"
DEVICE_SPECS[ipad-9.7-landscape]="1200x900"
# Apple TV
DEVICE_SPECS[appletv]="1920x1080"
# Mac
DEVICE_SPECS[mac]="1920x1080"
# Apple Vision Pro
DEVICE_SPECS[visionpro]="3840x2160"

# Required specs for App Store submission (mandatory sizes)
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
Usage: $SCRIPT_NAME [OPTIONS] <input-video>

Process screen recordings into App Store preview format.

OPTIONS:
    -d, --device <device>     Target device (see list below)
    -o, --output <path>       Output file path (default: auto-generated)
    -O, --output-dir <dir>    Output directory (default: same as input)
    -a, --all                 Generate all required sizes from input
    -p, --portrait            Force portrait orientation
    -l, --landscape           Force landscape orientation
    -t, --trim <start:end>    Trim video (e.g., "0:30" for first 30 seconds)
    -s, --scale <mode>        Scale mode: fit, fill, crop (default: fit)
    --prores                  Output ProRes 422 HQ instead of H.264
    --dry-run                 Show what would be done without executing
    -v, --verbose             Verbose output
    -h, --help                Show this help message

DEVICES:
    iPhone:
        iphone-6.9      6.9" (iPhone 16 Pro Max, etc.) - REQUIRED
        iphone-6.5      6.5" (iPhone 14 Plus, 13 Pro Max, etc.)
        iphone-6.3      6.3" (iPhone 16 Pro, 15 Pro, etc.)
        iphone-6.1      6.1" (iPhone 16, 14, 13, etc.)
        iphone-5.5      5.5" (iPhone 8 Plus, etc.)
        iphone-4.7      4.7" (iPhone SE, 8, etc.)

    iPad:
        ipad-13         13" (iPad Pro, iPad Air) - REQUIRED
        ipad-11         11" (iPad Pro, iPad Air, iPad mini)
        ipad-10.5       10.5" (iPad Pro, iPad Air 3rd gen)
        ipad-9.7        9.7" (older iPads)

    Other:
        appletv         Apple TV (1920x1080)
        mac             Mac (1920x1080)
        visionpro       Apple Vision Pro (3840x2160)

EXAMPLES:
    # Process for 6.9" iPhone in portrait
    $SCRIPT_NAME -d iphone-6.9 -p recording.mov

    # Generate all required sizes
    $SCRIPT_NAME -a recording.mov

    # Trim to 25 seconds and process
    $SCRIPT_NAME -d iphone-6.9 -t 0:25 recording.mov

    # Output ProRes for editing
    $SCRIPT_NAME -d ipad-13 --prores recording.mov

EOF
}

list_devices() {
    echo "Available devices:"
    for device in "${!DEVICE_SPECS[@]}"; do
        echo "  $device: ${DEVICE_SPECS[$device]}"
    done | sort
}

detect_orientation() {
    local input="$1"
    local width height

    width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$input")
    height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input")

    if [[ $width -gt $height ]]; then
        echo "landscape"
    else
        echo "portrait"
    fi
}

get_video_duration() {
    local input="$1"
    ffprobe -v error -show_entries format=duration -of csv=p=0 "$input"
}

validate_duration() {
    local duration="$1"
    local duration_int
    duration_int=$(printf "%.0f" "$duration")

    if [[ $duration_int -lt 15 ]]; then
        log_error "Video duration (${duration_int}s) is less than minimum 15 seconds"
        return 1
    elif [[ $duration_int -gt 30 ]]; then
        log_warn "Video duration (${duration_int}s) exceeds 30 seconds; consider trimming"
    fi
    return 0
}

get_output_filename() {
    local input="$1"
    local device="$2"
    local orientation="$3"
    local output_dir="$4"
    local extension="$5"

    local basename
    basename=$(basename "$input" | sed 's/\.[^.]*$//')

    echo "${output_dir}/${basename}_${device}_${orientation}.${extension}"
}

# ============================================================================
# Video Processing
# ============================================================================

build_scale_filter() {
    local target_width="$1"
    local target_height="$2"
    local scale_mode="$3"

    case "$scale_mode" in
        fit)
            # Scale to fit within bounds, add letterbox/pillarbox if needed
            echo "scale=${target_width}:${target_height}:force_original_aspect_ratio=decrease,pad=${target_width}:${target_height}:(ow-iw)/2:(oh-ih)/2:black"
            ;;
        fill)
            # Scale to fill bounds, crop excess
            echo "scale=${target_width}:${target_height}:force_original_aspect_ratio=increase,crop=${target_width}:${target_height}"
            ;;
        crop)
            # Center crop to exact size
            echo "crop=${target_width}:${target_height}"
            ;;
        *)
            log_error "Unknown scale mode: $scale_mode"
            return 1
            ;;
    esac
}

process_video() {
    local input="$1"
    local output="$2"
    local target_resolution="$3"
    local scale_mode="$4"
    local use_prores="$5"
    local trim_spec="$6"
    local verbose="$7"
    local dry_run="$8"

    local target_width target_height
    target_width=$(echo "$target_resolution" | cut -d'x' -f1)
    target_height=$(echo "$target_resolution" | cut -d'x' -f2)

    local scale_filter
    scale_filter=$(build_scale_filter "$target_width" "$target_height" "$scale_mode")

    local ffmpeg_args=()
    ffmpeg_args+=(-i "$input")

    # Check if input has audio - if not, generate silent audio
    local has_audio
    has_audio=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$input" 2>/dev/null | head -1)
    if [[ -z "$has_audio" ]]; then
        log_info "No audio detected - generating silent audio track"
        ffmpeg_args+=(-f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=${AUDIO_SAMPLE_RATE}")
        ffmpeg_args+=(-shortest)
    fi

    # Add trim if specified
    if [[ -n "$trim_spec" ]]; then
        local start_time end_time
        start_time=$(echo "$trim_spec" | cut -d':' -f1)
        end_time=$(echo "$trim_spec" | cut -d':' -f2)
        ffmpeg_args+=(-ss "$start_time" -t "$end_time")
    fi

    # Video filters
    local vf="${scale_filter},fps=${MAX_FPS}"
    ffmpeg_args+=(-vf "$vf")

    if [[ "$use_prores" == "true" ]]; then
        # ProRes 422 HQ
        ffmpeg_args+=(-c:v prores_ks)
        ffmpeg_args+=(-profile:v 3)  # HQ profile
        ffmpeg_args+=(-vendor apl0)
        ffmpeg_args+=(-pix_fmt yuv422p10le)
    else
        # H.264
        ffmpeg_args+=(-c:v "$VIDEO_CODEC")
        ffmpeg_args+=(-profile:v "$VIDEO_PROFILE")
        ffmpeg_args+=(-level:v "$VIDEO_LEVEL")
        ffmpeg_args+=(-b:v "$VIDEO_BITRATE")
        ffmpeg_args+=(-maxrate "$MAX_BITRATE")
        ffmpeg_args+=(-bufsize "$MAX_BITRATE")
        ffmpeg_args+=(-pix_fmt "$PIXEL_FORMAT")
        ffmpeg_args+=(-movflags +faststart)
    fi

    # Audio - use Apple's native AAC encoder on macOS for best compatibility
    if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "aac_at"; then
        ffmpeg_args+=(-c:a aac_at)
    else
        ffmpeg_args+=(-c:a "$AUDIO_CODEC")
        ffmpeg_args+=(-aac_coder twoloop)
    fi
    ffmpeg_args+=(-b:a "$AUDIO_BITRATE")
    ffmpeg_args+=(-ar "$AUDIO_SAMPLE_RATE")
    ffmpeg_args+=(-ac 2)
    ffmpeg_args+=(-channel_layout stereo)

    # Output
    ffmpeg_args+=(-y "$output")

    if [[ "$verbose" == "true" ]]; then
        log_info "FFmpeg command: ffmpeg ${ffmpeg_args[*]}"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ffmpeg ${ffmpeg_args[*]}"
        return 0
    fi

    log_info "Processing: $(basename "$input") -> $(basename "$output")"
    log_info "Target resolution: ${target_width}x${target_height}"

    if ffmpeg -hide_banner -loglevel warning "${ffmpeg_args[@]}"; then
        local output_size
        output_size=$(du -h "$output" | cut -f1)
        log_info "✅ Created: $output ($output_size)"
        return 0
    else
        log_error "❌ Failed to process video"
        return 1
    fi
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
    local trim_spec=""
    local scale_mode="fit"
    local use_prores="false"
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
            -t|--trim)
                trim_spec="$2"
                shift 2
                ;;
            -s|--scale)
                scale_mode="$2"
                shift 2
                ;;
            --prores)
                use_prores="true"
                shift
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

    # Set output directory
    if [[ -z "$output_dir" ]]; then
        output_dir=$(dirname "$input")
    fi
    mkdir -p "$output_dir"

    # Determine file extension
    local extension="mp4"
    if [[ "$use_prores" == "true" ]]; then
        extension="mov"
    fi

    # Detect orientation if not forced
    local orientation
    if [[ -n "$force_orientation" ]]; then
        orientation="$force_orientation"
    else
        orientation=$(detect_orientation "$input")
    fi
    log_info "Detected orientation: $orientation"

    # Validate duration
    local duration
    duration=$(get_video_duration "$input")
    if ! validate_duration "$duration"; then
        exit 1
    fi
    log_info "Video duration: $(printf "%.1f" "$duration")s"

    # Process videos
    if [[ "$generate_all" == "true" ]]; then
        # Generate all required sizes
        log_info "Generating all required App Store preview sizes..."

        local devices_to_process=()

        # Determine which devices to process based on orientation
        if [[ "$orientation" == "portrait" ]]; then
            devices_to_process+=("${REQUIRED_IPHONE}-portrait" "${REQUIRED_IPAD}-portrait")
        else
            devices_to_process+=("${REQUIRED_IPHONE}-landscape" "${REQUIRED_IPAD}-landscape")
        fi

        for target_device in "${devices_to_process[@]}"; do
            local target_res="${DEVICE_SPECS[$target_device]}"
            local device_base
            device_base=$(echo "$target_device" | sed 's/-portrait$//' | sed 's/-landscape$//')
            local out_file
            out_file=$(get_output_filename "$input" "$device_base" "$orientation" "$output_dir" "$extension")

            process_video "$input" "$out_file" "$target_res" "$scale_mode" "$use_prores" "$trim_spec" "$verbose" "$dry_run"
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
        if (( ${+DEVICE_SPECS[$full_device_key]} )); then
            target_res="${DEVICE_SPECS[$full_device_key]}"
        elif (( ${+DEVICE_SPECS[$device]} )); then
            target_res="${DEVICE_SPECS[$device]}"
            full_device_key="$device"
        else
            log_error "Unknown device: $device"
            list_devices
            exit 1
        fi

        # Determine output path
        if [[ -z "$output" ]]; then
            output=$(get_output_filename "$input" "$device" "$orientation" "$output_dir" "$extension")
        fi

        process_video "$input" "$output" "$target_res" "$scale_mode" "$use_prores" "$trim_spec" "$verbose" "$dry_run"
    fi

    log_info "Processing complete!"
}

main "$@"
