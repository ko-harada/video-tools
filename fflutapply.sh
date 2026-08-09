#!/bin/bash

function usage() {
	cat <<EOS
$0 [fghsr] dirs, ...
-f, --force		force write output if already exists.
-g, --gpu	 	use GPU (default NO)
-s, --stabilize	enable video stabilization (default NO)
-r, --rate		frame rate (default 24)
EOS
}

MOVS=()
HISTORY=2

SKIP=NO
FRAMERATE=24
FORCE=NO
GPU=NO
STABILIZE=NO
IS_PNG=NO
SS="00:00:04"
CRF=18

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=YES
            shift
            ;;
        -k|--skip)
            SKIP=YES
            shift
            ;;
        -s|--stabilize)
            STABILIZE=YES
            shift
            ;;
        -c|--crf)
            CRF="$2"
            shift
            shift
            ;;
        -r|--rate)
            FRAMERATE="$2"
            shift
            shift
            ;;
        -p|--png)
            IS_PNG=YES
            SS="${2:-00:00:04}"
            shift
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*|--*)
            echo "Unknown option $1"
            exit 1
            ;;
        *)
            MOVS+=("$1")
            shift
            ;;
    esac
done

set -- "${MOVS[@]}"

set -x

if [[ $# -eq 0 ]]; then
    echo "No file specified." >&2
    #MOVS=$(ls -1 exported/*.png)
    MOVS=$(ls -1 *.MOV)
else
    MOVS=${MOVS[@]}
fi
echo "Movies: $MOVS"


source $(dirname $0)/ffmpeg.sh

mkdir -p corrected

for mov in $MOVS
do
  # png="exported/${mov}.png"
  png="exported/${mov}.exr"
  # if [ -e corrected/${mov}.mp4 ]; then
  #   if [ $png -nt corrected/${mov}.mp4 ]; then
  #     process="Updating"
  #     for (( i = $HISTORY; i > 0; i-- )); do
  #       if [[ -e corrected/${mov}.$i.mp4 ]]; then
  #         mv corrected/${mov}.$i.mp4 corrected/${mov}.$((i+1)).mp4
  #       fi
  #     done
  #     mv corrected/${mov}.mp4 corrected/${mov}.1.mp4
  #   else
  #     echo "Skipped: corrected/${mov}.mp4 already exists."
  #     continue
  #   fi
  # else
  #   if [ -e ${mov} ]; then
  #     process="Generating"
  #   else
  #     echo "Skipped: ${mov} does not found."
  #     continue
  #   fi
  # fi

  ext=${mov##*.}
  file=${mov%%.*}
  OUTPUT="corrected/${file}.mp4"

  if [[ ! -e $png ]]; then
      echo "Skipping. ${png} not found." >&2
      continue
  fi
  if [[ "$IS_PNG" == "YES" ]]; then
      SSOPT="-ss $SS"
      OUTPUT="-c:v png -frames:v 1 -update 1 corrected/${mov%.MOV}.png"
  fi

  if [[ "$SKIP" == "YES" && -e ${OUTPUT} ]]; then
    echo "Skipping: ${OUTPUT} already exists." >&2
    continue
  fi

  if [[ "$OUTPUT" -nt "$png" ]]; then
    echo "Skipping: ${OUTPUT} is newer than ${png}." >&2
    continue
  fi

  echo "$process ${mov}."
  nice -n 19 ionice -c2 -n7 \
  ffmpeg \
    $SSOPT -i $mov -i $png \
    -filter_complex "
      [0:v]
        zscale=
          primaries=bt709:
          transfer=linear,
        format=gbrpf32le
        [vid];
      [vid][1:v]
        haldclut,
        zscale=primaries=bt709:transfer=bt709:matrix=bt709:range=full,
        format=yuv422p10le
    " \
    -color_primaries bt709 \
    -color_trc bt709 \
    -colorspace bt709 \
    -color_range full \
    -c:v libx265 -pix_fmt yuv422p10le \
    -crf $CRF -preset slow \
    -x265-params profile=main422-10 \
    -c:a copy \
    $(histfile $OUTPUT $HISTORY)

    #    zscale=primaries=bt709:rangein=full:range=full

    # -c:v prores_ks -v:profile 3 \
    # -c:a copy \
    # $(histfile $OUTPUT $HISTORY)

    # -i $png \
    # -filter_complex "
    #   [0:v]
    #     zscale=primaries=bt709:transfer=bt709:rangein=full:range=full,
    #     format=rgb48le[vid];
    #   [vid][1:v]
    #     haldclut,
    #     zscale=primaries=bt709:transfer=bt709:matrix=bt709:range=full,
    #     format=yuv422p10le
    # " \

    #  [0:v]
    #    zscale=primaries=bt709:transfer=bt709:rangein=full:range=full,
    #    format=rgb48le[vid];
    #  [1:v]
    #    zscale=transfer=iec61966-2-1:rangein=full:range=full
    #    [lut];
    #  [vid][lut]
    #    haldclut,
    #    zscale=primaries=bt709:transfer=bt709:matrix=bt709:range=full,
    #    format=yuv422p10le



    #    zscale=primaries=bt709:transfer=bt709:matrix=bt709:range=full,
    #    zscale=primaries=iec61966-2-1:rangein=full:range=full
    # -sws_flags spline+accurate_rnd+full_chroma_int+full_chroma_inp \
    # $OUTPUT

    #-c:v libx264 -preset slow -crf 18 \

    # -filter_complex "
    #   [0:v]
    #     zscale=primaries=bt709:transfer=bt709:rangein=full:range=full,
    #     zscale=transfer=iec61966-2-1,
    #     format=rgb48le[vid];
    #   [1:v]
    #     zscale=primaries=bt709:transfer=iec61966-2-1:rangein=full:range=full,
    #     format=rgb48le[lut];
    #   [vid][lut]
    #     haldclut,
    #     zscale=primaries=bt709:transfer=bt709:matrix=bt709,
    #     format=yuv422p
    # " \


    # -color_range full -color_primaries bt709 -color_trc bt709 -colorspace bt709 \

    #corrected/${mov}.mp4
    #-ss 00:00:04 -frames:v 1 \
    #corrected/${mov}.png

    # 12/23 なぜかピアノ発表会のがうまくいかない
    #  [0:v]zscale=primaries=bt709:transfer=bt709:rangein=full:range=full,format=rgb48le[vid];
    #  [1:v]zscale=primaries=bt709:transfer=iec61966-2-1:rangein=full:range=full,format=rgb48le[lut];
    #  [vid][lut]haldclut,zscale=primaries=bt709:transfer=bt709:matrix=bt709:rangein=full:range=full,format=yuv422p;

    # limited 用を意図したけどうまく行っていないfilter
    #  [0:v]zscale=primaries=bt709:transfer=bt709:rangein=full:range=limited,format=rgb48le[vid];
    #  [1:v]zscale=primaries=bt709:transfer=iec61966-2-1:rangein=limited:range=limited,format=rgb48le[lut];
    #  [vid][lut]haldclut,zscale=primaries=bt709:transfer=bt709:matrix=bt709;

    # full rangeとしてはうまく行っているfilter
    #  [0:v]zscale=primaries=bt709:transfer=bt709:rangein=full:range=full,format=rgb48le[vid];
    #  [1:v]zscale=primaries=bt709:transfer=iec61966-2-1:rangein=full:range=full,format=rgb48le[lut];
    #  [vid][lut]haldclut,zscale=primaries=bt709:transfer=bt709:matrix=bt709:rangein=full:range=full,format=yuv422p;

    # -filter_complex format=rgb48,haldclut=interp=tetrahedral \

    #-filter_complex "
    #  [0:v]zscale=primaries=bt709:transfer=iec61966-2-1:matrix=bt709:rangein=full:range=full,format=rgb48le[vid];
    #  [1:v]zscale=primaries=bt709:transfer=iec61966-2-1:matrix=bt709:rangein=full:range=full,format=rgb48le[lut];
    #  [vid][lut]haldclut;
    #" \

    #-c:v libx264 -preset slow -crf 18 \
    #-c:a copy \
    #corrected/${mov}.mp4

    # LUMIX S1 V-Log
    #  [0:v]zscale=primaries=bt709:transfer=iec61966-2-1:matrix=bt709:rangein=full:range=full,format=rgb48le[lut];
    #
    #  ffprobe: color_range=pc color_space=bt709 color_transfer=bt709 color_primaries=bt709 pix_fmt=yuv422p10le

    # SIGMA fpL MOV 8bit
    #  [0:v]zscale=primaries=bt709:transfer=bt709:matrix=bt709:rangein=full:range=full[vid];
    #
    #  ffprobe: color_range=pc color_space=bt709 color_transfer=bt709 color_primaries=bt709 pix_fmt=yuvj420p

    #-ss 00:00:04 -frames:v 1 \
    #corrected/${mov}.png \

    #  [0:v]zscale=rangein=full:range=full,format=rgb48le[vid];
    #  [1:v]zscale=primaries=bt709:transfer=iec61966-2-1:matrix=bt709:rangein=full:range=full,format=rgb48le[lut];

    # -c:v libx264 -preset slow -crf 18 \
    # -c:a copy \
    #corrected/${mov}.mp4 \
    #-hide_banner -stats -loglevel error

    # -filter_complex format=rgb48,haldclut=interp=tetrahedral \
    # -i $png -color_primaries bt709 -color_trc iec61966-2-1 -colorspace bt709 \

    # stdbuf -oL grep --line-buffered "frame=" |
    # awk '{printf "\r%s", $0; fflush() } END{ print "" }'
  # ffmpeg -loglevel 16 \
  #   -i $mov \
  #   -i $png \
  #   -sws_flags spline+accurate_rnd+full_chroma_int \
  #   -filter_complex format=rgb48,haldclut=interp=tetrahedral \
  #   -c:v libx264 -preset slow -crf 18 \
  #   -c:a copy \
  #   corrected/${mov}.mp4


    #-filter_complex format=rgb48,haldclut=interp=tetrahedral,scale=in_range=full:out_range=full:in_color_matrix=bt709:out_color_matrix=bt709 \
    #-color_range 1 -colorspace 1 -color_primaries 1 -color_trc 1 \

  # https://zenn.dev/razokulover/scraps/4282a6911e4ca7
  # ffmpeg -stream_loop -1 -i base.png -stream_loop -1 -i overlay.png -sws_flags spline+accurate_rnd+full_chroma_int \
  # -filter_complex "[1:v] format=yuva444p,colorspace=bt709:iall=bt601-6-525:fast=1[a];[a][0:v] overlay=100:100" \
  # -color_range 1 -colorspace 1 -color_primaries 1 -color_trc 1 -codec:a copy -t 3 -y output.mp4

  #  -filter_complex format=rgb48,haldclut=interp=tetrahedral,scale=in_range=full:out_range=full:in_color_matrix=bt709:out_color_matrix=bt709 \
  #  -filter_complex format=rgb48,haldclut=interp=tetrahedral,scale=in_range=full:out_range=mpeg:in_transfer=gamma22:out_transfer=bt709:out_color_matrix=bt709 \
  # NG:clipping worse -filter_complex haldclut=interp=tetrahedral,scale=out_color_matrix=bt709 \
  #  -filter_complex format=rgb48,haldclut=interp=tetrahedral,scale=out_color_matrix=bt709 \

  # ffmpeg \
  #   -vaapi_device /dev/dri/renderD128 \
  #   -i $mov \
  #   -i $png \
  #   -filter_complex haldclut \
  #   -c:v h264_vaapi -qp 16 -preset slow \
  #   -c:a aac \
  #   corrected/${mov}.mp4

done

#ffmpeg -i $1 \
#  -i png/exported_$1.png \
#  -filter_complex haldclut \
#  #-pix_fmt yuv420p \
#  -c:v libx264 -preset slow -crf 18 \
#  -c:a copy \
#  corrected/$1.mp4
