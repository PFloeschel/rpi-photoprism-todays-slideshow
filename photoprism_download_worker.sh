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

  #format=$(convert /tmp/pp_client-$count json: | jq -r ".[].image.format" | tr '[:upper:]' '[:lower:]')
  format=$(identify -format '%[compression]' /tmp/pp_client-$count  | tr '[:upper:]' '[:lower:]')

  echo "$format"
  if [[ -z "$format" ]]; then
    #format=$(ffprobe -v quiet -print_format json -show_format /tmp/pp_client-$count |jq )
    #format=$(ffprobe -v quiet -print_format json -show_format /tmp/pp_client-$count | jq 'map(.format_name |= split(","))' | jq -r '.[0].format_name.[0]')
    #echo "$format"
    #mv /tmp/pp_client-$count /tmp/pp_client-$count.$format

    format="gif"
    ffmpeg -i /tmp/pp_client-$count -filter_complex "[0:v] palettegen" /tmp/pp_client-$count-palette.png
    ffmpeg -i /tmp/pp_client-$count -i /tmp/pp_client-$count-palette.png -filter_complex "[0:v] fps=10 [new];[new][1:v] paletteuse" /tmp/pp_client-$count-resized.$format
  else
    convert -monitor -adaptive-resize 1920x1080 /tmp/pp_client-$count /tmp/pp_client-$count-resized.$format
  fi
  echo -e "Finished conversion $count / $length"

  mv -f /tmp/pp_client-$count-resized.$format images/$image_date--$count.$format
  rm /tmp/pp_client-$count*
