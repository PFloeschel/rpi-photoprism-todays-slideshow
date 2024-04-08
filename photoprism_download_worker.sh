#!/bin/bash

count=$1
length=$2
base_url_dl=$3
image_dl=$4
image_date=$5


API_KEY_BING=
API_KEY_LOCIQ=
DL_LIMIT=
THREAD_LIMIT=
source photoprism_download_worker.env


# Download Images
logger -t pp_client "Starting download + conversion  $count / $length"
echo -e "\nDownloading $count / $length"

curl -s -S --limit-rate $DL_LIMIT -o /tmp/pp_client-$count $base_url_dl$image_dl

format=$(identify -limit thread $THREAD_LIMIT -format '%m\n' /tmp/pp_client-$count  | tr '[:upper:]' '[:lower:]' | head -n1 )

echo "$count : $format"

# VIDEO
if [[ -z "$format" ]]; then
  format=$(ffprobe -threads $THREAD_LIMIT -hide_banner -show_format -print_format json /tmp/pp_client-$count | jq -r .format.format_name | cut -d, -f1)
  format=$(echo "${format//_pipe}")
  cp -f /tmp/pp_client-$count movies/$image_date--$count.$format

  #format="webp"
  #ffmpeg -hide_banner -threads $THREAD_LIMIT -t 5 -i /tmp/pp_client-$count -vcodec libwebp -r 5 -loop 0 /tmp/pp_client-$count-resized.$format

  format="avif"
  ffmpeg -hide_banner -threads $THREAD_LIMIT -t 10 -i /tmp/pp_client-$count -pix_fmt yuv420p -r 1 -f yuv4mpegpipe /tmp/pp_client-$count.y4m
  avifenc -p /tmp/pp_client-$count.y4m /tmp/pp_client-$count-resized.$format -j all

# PHOTO
else
  # JPEG
  #format="jpeg"
  #convert -limit thread $THREAD_LIMIT -adaptive-resize 1920x1080 -quality 100 /tmp/pp_client-$count /tmp/pp_client-$count-resized.$format

  # HEIC
  format="heic"
  convert -limit thread $THREAD_LIMIT -adaptive-resize 1920x1080 -quality 100 /tmp/pp_client-$count /tmp/pp_client-$count-resized.$format

  # PNG / AVIF
  #format="png"
  #convert -limit thread $THREAD_LIMIT -adaptive-resize 1920x1080 /tmp/pp_client-$count /tmp/pp_client-$count-resized.$format

  # Simplify EXIF for viewing
  filename="/tmp/pp_client-$count-resized.$format"
  # simplify camera and exif data
  exiftool -EXIFIFD:all= $filename
  exiftool '-MODEL<$MAKE $MODEL' $filename
  exiftool -MAKE= -SOFTWARE= $filename

  # Get EXIF GPS
  exif_loc=$(exiftool -F -m -location:all -c %+.8f -j $filename)

  exif_lat=$(echo "$exif_loc" | jq -r .[].GPSLatitude)
  exif_lon=$(echo "$exif_loc" | jq -r .[].GPSLongitude)
  exif_alt=$(echo "$exif_loc" | jq -r .[].GPSAltitude)

  # GPS --> address
  if [ "$exif_lat" != null ] && [[ -n "$exif_lat" ]] ;
   then

    exif_lat=$(echo "${exif_lat//+}")
    exif_lon=$(echo "${exif_lon//+}")

    echo "$count : GPS: $exif_lat,$exif_lon"
    # LocationIQ
    #   geo_resp=$(curl -s -S --request GET --limit-rate $DL_LIMIT \
    #     --url "https://eu1.locationiq.com/v1/reverse?lat=$exif_lat&lon=$exif_lon&normalizeaddress=1&addressdetails=1&format=json&accept-language=en&key=$>
    #     --header 'accept: application/json')
    #   #echo $geo_resp | jq .
    #   geo_loc=$(echo "$geo_resp" | jq -r '.address | .road + ", " + .city + ", " + .country')

    # BingMaps
    geo_resp=$(curl -s -S --limit-rate $DL_LIMIT \
       "http://dev.virtualearth.net/REST/v1/Locations/$exif_lat,$exif_lon?key=$API_KEY_BING" )
    #echo $geo_resp | jq .
    geo_loc=$(echo "$geo_resp" | jq -r .resourceSets.[].resources[].name)
    geo_loc=$(echo "$geo_loc, $exif_alt")

    echo "$count : $geo_loc"
    exiftool "-SOFTWARE=$geo_loc" $filename

   else
    echo "$count : No GPS data found."
  fi

  #format="avif"
  #avifenc -q 95 -p /tmp/pp_client-$count.png /tmp/pp_client-$count-resized.$format -j all
fi

# MOVE from /tmp
mv -f /tmp/pp_client-$count-resized.$format images/$image_date--$count.$format
rm /tmp/pp_client-$count*

# Get GPS maps
if [ "$exif_lat" != null ] && [[ -n "$exif_lat" ]] ;
 then
  echo "$count : Loading area maps"

  # LocationIQ
  #  curl -s -S --limit-rate $DL_LIMIT \
  #    "https://maps.locationiq.com/v3/staticmap?size=960x540&scale=2&markers=icon:small-red-cutout|$exif_lat,$exif_lon&zoom=11&key=$API_KEY_LOCIQ" \
  #    -o "images/$image_date--$count.map1.png"
  #  curl -s -S --limit-rate $DL_LIMIT \
  #    "https://maps.locationiq.com/v3/staticmap?size=960x540&scale=2&markers=icon:small-red-cutout|$exif_lat,$exif_lon&zoom=16&key=$API_KEY_LOCIQ" \
  #    -o "images/$image_date--$count.map2.png"

  # BingMaps
    curl -s -S --limit-rate $DL_LIMIT \
      "https://dev.virtualearth.net/REST/v1/Imagery/Map/AerialWithLabels?mS=1920,1080&dpi=Large&fmt=png&pp=$exif_lat,$exif_lon;46&zoomLevel=11&key=$API_KEY_BING" \
      -o "images/$image_date--$count.map1.png"
    curl -s -S --limit-rate $DL_LIMIT \
      "https://dev.virtualearth.net/REST/v1/Imagery/Map/AerialWithLabels?mS=1920,1080&dpi=Large&fmt=png&pp=$exif_lat,$exif_lon;46&zoomLevel=15&key=$API_KEY_BING" \
      -o "images/$image_date--$count.map2.png"
    curl -s -S --limit-rate $DL_LIMIT \
      "https://dev.virtualearth.net/REST/v1/Imagery/Map/AerialWithLabels?mS=1920,1080&dpi=Large&fmt=png&pp=$exif_lat,$exif_lon;46&zoomLevel=18&key=$API_KEY_BING" \
      -o "images/$image_date--$count.map3.png"

  #convert -limit thread $THREAD_LIMIT -quality 100 images/$image_date--$count.map1.png images/$image_date--$count.map1.heic
  #convert -limit thread $THREAD_LIMIT -quality 100 images/$image_date--$count.map2.png images/$image_date--$count.map2.heic
  #convert -limit thread $THREAD_LIMIT -quality 100 images/$image_date--$count.map3.png images/$image_date--$count.map3.heic
  #rm images/$image_date--$count.map?.png
fi

# Remove files smaller 1024 bytes - cannot be interesting images
filename="images/$image_date--$count.$format"
filesize=$(wc -c $filename | awk '{print $1}')
if [ "$filesize" -lt "1024" ]; then
  rm $filename
fi

echo -e "Finished download + conversion  $count / $length"
logger -t pp_client "Finished download + conversion  $count / $length"
