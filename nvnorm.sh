#!/bin/bash

set -euo pipefail

# ============================================================
# LUMIX S1 C4K -> HEVC NVENC + 2-pass loudnorm
#
# Input:
#   *.MOV / *.mov / *.MP4 / *.mp4
#
# Output:
#   nv_<filename>.mp4
#
# Requires:
#   ffmpeg
#   ffprobe
#   jq
# ============================================================

# ---------- Settings ----------

# loudnorm
TARGET_I="-16"
TARGET_TP="-1.5"
TARGET_LRA="11"

# NVENC
PRESET="p5"
CQ="20"

# Audio
AUDIO_BITRATE="192k"

# ---------- Check commands ----------

for cmd in ffmpeg ffprobe jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: $cmd が見つかりません"
        exit 1
    fi
done

# ---------- Process files ----------

shopt -s nullglob

files=(
    *.MOV *.mov
    *.MP4 *.mp4
)

if [ ${#files[@]} -eq 0 ]; then
    echo "動画ファイルが見つかりません。"
    exit 0
fi

for input in "${files[@]}"; do

    # Skip our own output
    if [[ "$input" == nv_* ]]; then
        continue
    fi

    base="${input%.*}"
    output="nv_${base}.mp4"

    echo
    echo "============================================================"
    echo "Input : $input"
    echo "Output: $output"
    echo "============================================================"

    # Temporary files
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    loudnorm_log="$tmpdir/loudnorm.log"

    # --------------------------------------------------------
    # Pass 1 : measure loudness
    # --------------------------------------------------------

    echo
    echo "[1/2] Loudness analysis..."

    ffmpeg -hide_banner -nostats \
        -i "$input" \
        -map 0:a:0 \
        -af "loudnorm=I=${TARGET_I}:TP=${TARGET_TP}:LRA=${TARGET_LRA}:print_format=json" \
        -f null - \
        2> "$loudnorm_log"

    # Extract JSON object printed by loudnorm
    loudnorm_json="$tmpdir/loudnorm.json"

    sed -n '/^{/,/^}/p' "$loudnorm_log" > "$loudnorm_json"

    if ! jq empty "$loudnorm_json" >/dev/null 2>&1; then
        echo "ERROR: loudnormの測定結果を取得できませんでした。"
        cat "$loudnorm_log"
        exit 1
    fi

    measured_I=$(jq -r '.input_i' "$loudnorm_json")
    measured_TP=$(jq -r '.input_tp' "$loudnorm_json")
    measured_LRA=$(jq -r '.input_lra' "$loudnorm_json")
    measured_thresh=$(jq -r '.input_thresh' "$loudnorm_json")
    measured_offset=$(jq -r '.target_offset' "$loudnorm_json")

    echo
    echo "Measured:"
    echo "  I      = $measured_I LUFS"
    echo "  TP     = $measured_TP dBTP"
    echo "  LRA    = $measured_LRA LU"
    echo "  Offset = $measured_offset dB"

    # --------------------------------------------------------
    # Pass 2 : encode
    # --------------------------------------------------------

    echo
    echo "[2/2] Encoding..."

    ffmpeg -hide_banner \
        -i "$input" \
        -map 0:v:0 \
        -map 0:a:0 \
        \
        -vf "
            scale=in_range=full:out_range=tv,
            format=p010le
        " \
        \
        -c:v hevc_nvenc \
        -preset "$PRESET" \
        -tune hq \
        -rc vbr \
        -cq "$CQ" \
        -b:v 0 \
        -multipass fullres \
        -color_range tv \
        \
        -c:a aac \
        -b:a "$AUDIO_BITRATE" \
        -af "loudnorm=I=${TARGET_I}:TP=${TARGET_TP}:LRA=${TARGET_LRA}:measured_I=${measured_I}:measured_TP=${measured_TP}:measured_LRA=${measured_LRA}:measured_thresh=${measured_thresh}:offset=${measured_offset}:linear=true:print_format=summary" \
        \
        -map_metadata 0 \
        -movflags +faststart \
        "$output"

    echo
    echo "Done: $output"

    rm -rf "$tmpdir"
    trap - EXIT

done

echo
echo "All files completed."
