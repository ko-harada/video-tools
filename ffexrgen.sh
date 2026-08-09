#!/bin/bash

mkdir -p exr

HALDCLUTSRC=13
SS="00:00:04"

# haldclutsrc x scale mapping
scale=(
  0     # 0
  0     # 1
  8     # 2：8×8
  27    # 3：27×27
  64    # 4：64×64
  125   # 5：125×125
  216   # 6：216×216
  343   # 7：343×343
  512   # 8：512×512
  729   # 9：729×729
  1000  # 10：1000×1000
  1331  # 11：1331×1331
  1728  # 12：1728×1728
  2197  # 13：2197×2197
  2744  # 14：2744×2744
  3375  # 15：3375×3375
  4096  # 16：4096×4096
)

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--haldclutsrc)
            HALDCLUTSRC=$2
            shift
            shift
            ;;
        -s|--ss)
            SS=$2
            shift
            shift
            ;;
        -k|--skip)
            SKIP=yes
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

echo "HALDCLUTSRC=$HALDCLUTSRC, scale=${scale[$HALDCLUTSRC]}, SS=${SS}"
echo "[1]scale=-1:${scale[$HALDCLUTSRC]}[b];[0][b]hstack" \

if [[ $# -eq 0 ]]; then
    echo "No file specified." >&2
    MOVS=$(ls -1 *.MOV)
else
    MOVS=${MOVS[@]}
fi
echo "Movies: $MOVS"

for mov in $MOVS
do
  if [ -e exr/$mov.exr ]; then
    echo "Skipping. exr/$mov.exr already exists."
    continue
  fi

  echo "Generating HaldcLUT exr for $mov"
  nice -n 19 ionice -c2 -n7 \
  ffmpeg -loglevel 32 \
    -ss $SS -i $mov \
    -frames:v 1 \
    -vf "
      zscale=
        primaries=bt709:
        transfer=linear,
      format=gbrpf32le
    " \
    _frame.exr
    
    # -vf "
    #   zscale=
    #     primariesin=bt2020:
    #     transferin=arib-std-b67:
    #     primaries=bt709:
    #     transfer=linear,
    #   format=gbrpf32le
    # " \

    # -pix_fmt rgb48le \
    # gbrpf32le

  nice -n 19 ionice -c2 -n7 \
  ffmpeg -loglevel 16 \
    -f lavfi -i haldclutsrc=$HALDCLUTSRC \
    -frames:v 1 \
    -vf format=gbrpf32le \
    _hald.exr
  #  -pix_fmt rgb48le \

  nice -n 19 ionice -c2 -n7 \
  ffmpeg -loglevel 16 \
    -i _hald.exr \
    -i _frame.exr \
    -filter_complex "
        [1]scale=-1:${scale[$HALDCLUTSRC]}[b];[0][b]hstack
    " \
    -pix_fmt gbrpf32le \
    exr/$mov.exr

  rm -f _frame.exr _hald.exr

  # nice -n 19 ionice -c2 -n7 \
  # ffmpeg -loglevel 16 \
  #   -ss $SS -f lavfi -i haldclutsrc=$HALDCLUTSRC \
  #   -ss $SS -i $mov \
  #   -frames:v 1 \
  #   -filter_complex "
  #       [1]scale=-1:${scale[$HALDCLUTSRC]}[b];[0][b]hstack
  #   " \
  #   -pix_fmt rgb48le \
  #   exr/$mov.exr

    # -pix_fmt gbrp10le \
    # -pix_fmt rgb48le \

    #
    # haldclutsrc と scale の関係
    # 2：8×8
    # 3：27×27
    # 4：64×64
    # 5：125×125
    # 6：216×216
    # 7：343×343
    # 8：512×512
    # 9：729×729
    # 10：1000×1000
    # 11：1331×1331
    # 12：1728×1728
    # 13：2197×2197
    # 14：2744×2744
    # 15：3375×3375
    # 16：4096×4096
done

# ffmpeg -f lavfi -i haldclutsrc=8 \
#   -i $1 -ss 0:00:04 -frames:v 1 \
#   -filter_complex "[1]scale=-1:512[b];[0][b]hstack" \
#   exr/$1.exr
