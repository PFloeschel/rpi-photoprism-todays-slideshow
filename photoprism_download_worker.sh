#!/bin/bash

count=$1
length=$2
base_url_dl=$3
image_dl=$4
image_date=$5

dl_limit=2M
thread_limit=8

# Download Images
  echo -e "\nDownloading $count / $length"
  logger -t pp_client "Starting download + conversion  $count / $length"

  curl -s -S --limit-rate $dl_limit -o /tmp/pp_client-$count $base_url_dl$image_dl

  #format=$(identify -limit thread $thread_limit -format '%[compression]' /tmp/pp_client-$count  | tr '[:upper:]' '[:lower:]')
  format=$(identify -limit thread $thread_limit -format '%m\n' /tmp/pp_client-$count  | tr '[:upper:]' '[:lower:]' | head -n1 )

  echo "$count : $format"
  if [[ -z "$format" ]]; then
    format=$(ffprobe -threads $thread_limit  -hide_banner -show_format -print_format json /tmp/pp_client-$count | jq -r .format.format_name | cut -d, -f1)
    cp -f /tmp/pp_client-$count movies/$image_date--$count.$format

    format="webp"
    ffmpeg -hide_banner -threads $thread_limit -t 5 -i /tmp/pp_client-$count -vcodec libwebp -filter:v fps=fps=5 -loop 0 /tmp/pp_client-$count-resized.$format
  else
    convert -limit thread $thread_limit -adaptive-resize 1920x1080 -quality 95 /tmp/pp_client-$count /tmp/pp_client-$count-resized.$format
  fi
  echo -e "Finished conversion $count / $length"

  mv -f /tmp/pp_client-$count-resized.$format images/$image_date--$count.$format
  rm /tmp/pp_client-$count*

  logger -t pp_client "Finished download + conversion  $count / $length"
