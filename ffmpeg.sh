function jpg2mp4_gpu() {
    WAV_INPUT=$1
    VIDEO_INPUT=$2
    FRAMERATE=$3
    OUTPUT=$4

    if [[ -e $OUTPUT ]]; then
        echo "$OUTPUT already exists. skipping." 1>&2
              return 0
    fi
    nice -n 19 ionice -c2 -n7 \
    ffmpeg -loglevel 16 \
        -vaapi_device /dev/dri/renderD128 \
        -i $WAV_INPUT -r $FRAMERATE -i $VIDEO_INPUT \
        -vf 'format=nv12,hwupload' \
        -c:v h264_vaapi -qp 16 -c:a aac \
        -r $FRAMERATE  $OUTPUT
}

function jpg2mp4_cpu() {
    WAV_INPUT=$1
    VIDEO_INPUT=$2
    FRAMERATE=$3
    OUTPUT=$4

    if [[ -e $OUTPUT ]]; then
        echo "$OUTPUT already exists. skipping." 1>&2
              return 0
    fi
    nice -n 19 ionice -c2 -n7 \
    ffmpeg -loglevel 16 \
        -i $WAV_INPUT -r $FRAMERATE -i $VIDEO_INPUT \
        -vf "format=yuv420p" \
        -c:v libx264 -crf 18 -c:a aac \
        -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
        -r $FRAMERATE $OUTPUT
}

function mov2mp4_cpu() {
    INPUT=$1

    nice -n 19 ionice -c2 -n7 \
    ffmpeg -loglevel 16 \
         -i $INPUT \
        -c:v h264 -crf 16 -c:a aac \
        ${INPUT%.*}.mp4
}


function stabilize_gpu() {
    INPUT_MP4=$1
    OUTPUT_MP4=$2

    if [[ -e ${INPUT_MP4%.*}.trf ]]; then
        echo "${INPUT_MP4%.*}.trf already exists. skipping." 1>&2
    else
        nice -n 19 ionice -c2 -n7 \
        ffmpeg -loglevel 16 \
        -i $INPUT_MP4 \
        -vf 'vidstabdetect=result='${INPUT_MP4%.*}.trf \
        -an -f null -
    fi

    if [[ -e $OUTPUT_MP4 ]]; then
        echo "${OUTPUT_MP4} already exists. skipping." 1>&2
              return 0
    else
        nice -n 19 ionice -c2 -n7 \
         ffmpeg -loglevel 16 \
        -vaapi_device /dev/dri/renderD128 -i $INPUT_MP4 \
        -vf 'vidstabtransform=input='${INPUT_MP4%.*}.trf',unsharp=5:5:0.8:3:3:0.4,format=nv12' \
        -c:v h264 -crf 18 -c:a copy $OUTPUT_MP4
    fi
    # ffmpeg -i $INPUT_MP4 -vf vidstabdetect -an -f null - && \
    #     ffmpeg -vaapi_device /dev/dri/renderD128 \
    #     -i $INPUT_MP4 -vf 'vidstabtransform,format=nv12,hwupload' \
    #     -c:v h264_vaapi -qp 16 -c:a copy $OUTPUT_MP4
}

function vidstabdetect() {
    local INPUT_MP4=$1

    if [[ -e ${INPUT_MP4%.*}.trf ]]; then
        echo "${INPUT_MP4%.*}.trf already exists. skipping." 1>&2
    else
        nice -n 19 ionice -c2 -n7 \
        ffmpeg -loglevel 16 \
        -i $INPUT_MP4 \
        -vf "vidstabdetect=result=${INPUT_MP4%.*}.trf:tripod=0" \
        -an -f null -
    fi
}

function vidstabtransform() {
    local INPUT_MP4=$1
    local OUTPUT_MP4=$2
    local ZOOM=${3:-5}
    if [[ -e $OUTPUT_MP4 ]]; then
        echo "${OUTPUT_MP4} already exists. skipping." 1>&2
              return 0
    else
        nice -n 19 ionice -c2 -n7 \
        ffmpeg -loglevel 16 \
        -i $INPUT_MP4 \
        -vf "
            vidstabtransform=input=${INPUT_MP4%.*}.trf:tripod=0:zoom=${ZOOM}:optzoom=2,
            unsharp=5:5:0.8:3:3:0.4,format=yuv422p
            " \
        -c:v h264 -crf 18 -c:a copy $OUTPUT_MP4
    fi
}

function stabilize() {
    INPUT_MP4=$1
    OUTPUT_MP4=$2

    if [[ -e ${INPUT_MP4%.*}.trf ]]; then
        echo "${INPUT_MP4%.*}.trf already exists. skipping." 1>&2
    else
        nice -n 19 ionice -c2 -n7 \
        ffmpeg -loglevel 16 \
        -i $INPUT_MP4 \
        -vf "vidstabdetect=result=${INPUT_MP4%.*}.trf:tripod=0" \
        -an -f null -
    fi

    if [[ -e $OUTPUT_MP4 ]]; then
        echo "${OUTPUT_MP4} already exists. skipping." 1>&2
              return 0
    else
        nice -n 19 ionice -c2 -n7 \
        ffmpeg -loglevel 16 \
        -i $INPUT_MP4 \
        -vf "vidstabtransform=input=${INPUT_MP4%.*}.trf:tripod=0,unsharp=5:5:0.8:3:3:0.4,format=yuv422p" \
        -c:v h264 -crf 18 -c:a copy $OUTPUT_MP4
    fi
    # ffmpeg -i $INPUT_MP4 -vf vidstabdetect -an -f null - && \
    #     ffmpeg -i $INPUT_MP4 -vf 'vidstabtransform,format=nv12' \
    #     -c:v h264 -crf 18 -c:a copy $OUTPUT_MP4
}

function check_dir() {
    DIR=$1
    if ! wav=$(ls $DIR/*.WAV | grep -e "^$DIR/A..._..._........\.WAV$"); then
        echo "$DIR: WARNING: No WAV file found" >&2
        return 1
    fi

    local last_dng=$(ls $DIR/*.DNG | tail -n 1)
    # if ! (ls $DIR/*.jpg | grep -e "^$DIR/A..._..._........_......\.jpg$" > /dev/null); then
    if ! [[ -e ${last_dng%.DNG}.jpg ]]; then
        echo "$DIR: WARNING: No jpeg file found" >&2
        return 1
    fi
    echo -n $wav
}


function histfile() {
    local ext=${1##*.}
    local file=${1%%.*}
    local history=${2:-2}
    local i
    if [ -e ${file}.${ext} ]; then
        for (( i = $history; i > 0; i-- )); do
            if [[ -e ${file}.$i.${ext} ]]; then
              mv ${file}.$i.${ext} ${file}.$((i+1)).{ext}
            fi
        done
        mv ${file}.${ext} ${file}.1.${ext}
    fi
    echo "${file}.${ext}"
}

