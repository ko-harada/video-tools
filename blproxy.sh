#!/bin/bash

# 🎯 引数で渡されたファイルを順に処理（*.mp4 など展開可）
if [ "$#" -eq 0 ]; then
  echo "❌ エラー: 少なくとも1つの動画ファイルを引数に指定してください。"
  echo "例: $0 *.mp4"
  exit 1
fi

if which nvidia-smi > /dev/null 2>&1 &&
    nvidia-smi -L > /dev/null 2>&1
then
    use_nvenc=true
else
    use_nvenc=false
fi

for input in "$@"; do
  if [[ ! -f "$input" ]]; then
    echo "⚠️ スキップ: ファイルが存在しません: $input"
    continue
  fi

  filename=$(basename "$input")           # 例: movie.mp4
  name="${filename%.*}"                   # 例: movie
  base_dir=$(dirname "$input")            # 元動画のある場所

  # Blender互換の保存先ディレクトリ
  proxy_dir="$base_dir/BL_proxy/$filename"
  mkdir -p "$proxy_dir"

  output_file="$proxy_dir/proxy_50.avi"

  # if [[ -f "$output_file" ]]; then
  if [[ "$output_file" -nt "$input" ]]; then
    echo "✅ 既に存在: $output_file"
    continue
  fi

  if [[ "$input" =~ \.[0-9]\. ]]; then
    echo "✅ ヒストリは除外: $input"
    continue
  fi

  echo "🔄 生成中: $output_file"

  if $use_nvenc; then
      nice -n 19 ionice -c2 -n7 \
      ffmpeg -y -i "$input" -loglevel 16 \
          -vf scale=iw*0.5:ih*0.5 \
          -c:v h264_nvenc -preset p1 -rc constqp -qp 23 \
          -g 10 -an \
          -pix_fmt yuv420p "$output_file"
  else
      nice -n 19 ionice -c2 -n7 \
      ffmpeg -y -i "$input" -loglevel 16 -vf scale=iw*0.5:ih*0.5 \
          -c:v libx264 -crf 23 -g 10 -preset ultrafast -tune fastdecode -an \
          -pix_fmt yuv420p "$output_file"
  fi

  echo "✅ 完了: $output_file"
done
