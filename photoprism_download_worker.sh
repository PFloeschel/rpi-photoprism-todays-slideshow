#!/bin/bash

count=$1
length=$2
base_url_dl=$3
image_dl=$4
image_date=$5

# Download Images
  echo -e "\nDownloading $count / $length"
  logger -t pp_client "Downloading $count / $length"

  curl -s -S -o /tmp/pp_client-$count $base_url_dl$image_dl

  format=$(identify -format '%[compression]' /tmp/pp_client-$count  | tr '[:upper:]' '[:lower:]')

  echo "$count : $format"
  if [[ -z "$format" ]]; then
    format="webp"
    ffmpeg -i /tmp/pp_client-$count -vcodec libwebp -filter:v fps=fps=5 -loop 0 /tmp/pp_client-$count-resized.$format
  else
    convert -limit thread 2 -adaptive-resize 1920x1080 -quality 100 /tmp/pp_client-$count /tmp/pp_client-$count-resized.$format
  fi
  echo -e "Finished conversion $count / $length"

  mv -f /tmp/pp_client-$count-resized.$format images/$image_date--$count.$format
  rm /tmp/pp_client-$count*
