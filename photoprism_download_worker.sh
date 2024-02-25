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

  #format=$(identify -limit thread $thread_limit -format '%[compression]' /tmp/pp_client-$count  | tr '[:upper:]' '[:lower:]')
  format=$(identify -limit thread $THREAD_LIMIT -format '%m\n' /tmp/pp_client-$count  | tr '[:upper:]' '[:lower:]' | head -n1 )

  echo "$count : $format"
  if [[ -z "$format" ]]; then
    format=$(ffprobe -threads $THREAD_LIMIT -hide_banner -show_format -print_format json /tmp/pp_client-$count | jq -r .format.format_name | cut -d, -f1)
    format=$(echo "${format//_pipe}")
    cp -f /tmp/pp_client-$count movies/$image_date--$count.$format

    format="webp"
    ffmpeg -hide_banner -threads $THREAD_LIMIT -t 5 -i /tmp/pp_client-$count -vcodec libwebp -r 5 -loop 0 /tmp/pp_client-$count-resized.$format
  else
    convert -limit thread $THREAD_LIMIT -adaptive-resize 1920x1080 -quality 95 /tmp/pp_client-$count /tmp/pp_client-$count-resized.$format
  fi

  mv -f /tmp/pp_client-$count-resized.$format images/$image_date--$count.$format
  rm /tmp/pp_client-$count*


# Simplify EXIF for viewing and get GPS location/maps

  filename="images/$image_date--$count.$format"
  # simplify camera and exif data
  exif_make=$(exiv2 -Pt -g "Exif.Image.Make" $filename)
  exif_model=$(exiv2 -Pt -g "Exif.Image.Model" $filename)
  exif_cam=$(echo "$exif_make $exif_model")
  #echo $exif_cam
  exiv2 -M "set Exif.Image.Make $exif_cam" $filename
  exiv2 -M 'del Exif.Image.Model' $filename
  exiv2 -M 'del Exif.Image.Software' $filename
  exiv2 -M 'del Exif.Photo.ExposureTime' $filename
  exiv2 -M 'del Exif.Photo.FNumber' $filename
  exiv2 -M 'del Exif.Photo.MakerNote' $filename

  # get exif GPS
  exif_loc=$(exiftool -F -m -location:all -c %+.8f -j $filename)

  exif_lat=$(echo "$exif_loc" | jq -r .[].GPSLatitude)
  exif_lon=$(echo "$exif_loc" | jq -r .[].GPSLongitude)
  exif_alt=$(echo "$exif_loc" | jq -r .[].GPSAltitude)

  if [ "$exif_lat" != null ] && [[ -n "$exif_lat" ]] ;
   then

    exif_lat=$(echo "${exif_lat//+}")
    exif_lon=$(echo "${exif_lon//+}")

    echo "$count : GPS: $exif_lat,$exif_lon"
    #GPS --> address
    #LocationIQ
    #   geo_resp=$(curl -s -S --request GET --limit-rate $DL_LIMIT \
    #     --url "https://eu1.locationiq.com/v1/reverse?lat=$exif_lat&lon=$exif_lon&normalizeaddress=1&addressdetails=1&format=json&accept-language=en&key=$API_KEY_LOCIQ" \
    #     --header 'accept: application/json')
    #   #echo $geo_resp | jq .
    #   geo_loc=$(echo "$geo_resp" | jq -r '.address | .road + ", " + .city + ", " + .country')

    #BingMaps
       geo_resp=$(curl -s -S --limit-rate $DL_LIMIT \
         "http://dev.virtualearth.net/REST/v1/Locations/$exif_lat,$exif_lon?key=$API_KEY_BING" )
       #echo $geo_resp | jq .
       geo_loc=$(echo "$geo_resp" | jq -r .resourceSets.[].resources[].name)

    geo_loc=$(echo "$geo_loc, $exif_alt")

    echo "$count : $geo_loc"
    exiv2 -M "add Exif.Image.Software $geo_loc" $filename

    echo "$count : Loading area maps"
    #LocationIQ
    #  curl -s -S --limit-rate $DL_LIMIT \
    #    "https://maps.locationiq.com/v3/staticmap?size=960x540&scale=2&markers=icon:small-red-cutout|$exif_lat,$exif_lon&zoom=11&key=$API_KEY_LOCIQ" \
    #    -o "images/$image_date--$count.map1.png"
    #  curl -s -S --limit-rate $DL_LIMIT \
    #    "https://maps.locationiq.com/v3/staticmap?size=960x540&scale=2&markers=icon:small-red-cutout|$exif_lat,$exif_lon&zoom=16&key=$API_KEY_LOCIQ" \
    #    -o "images/$image_date--$count.map2.png"

    #BingMaps
      curl -s -S --limit-rate $DL_LIMIT \
        "https://dev.virtualearth.net/REST/v1/Imagery/Map/AerialWithLabels?mS=1920,1080&dpi=Large&pp=$exif_lat,$exif_lon;46&zoomLevel=11&key=$API_KEY_BING" \
        -o "images/$image_date--$count.map1.jpg"
      curl -s -S --limit-rate $DL_LIMIT \
        "https://dev.virtualearth.net/REST/v1/Imagery/Map/AerialWithLabels?mS=1920,1080&dpi=Large&pp=$exif_lat,$exif_lon;46&zoomLevel=15&key=$API_KEY_BING" \
        -o "images/$image_date--$count.map2.jpg"
      curl -s -S --limit-rate $DL_LIMIT \
        "https://dev.virtualearth.net/REST/v1/Imagery/Map/AerialWithLabels?mS=1920,1080&dpi=Large&pp=$exif_lat,$exif_lon;46&zoomLevel=18&key=$API_KEY_BING" \
        -o "images/$image_date--$count.map3.jpg"

   else
    echo "$count : No GPS data found."
  fi

  # remove files smaller 1024 bytes - cannot be interesting images
  filesize=$(wc -c $filename | awk '{print $1}')
  if [ "$filesize" -lt "1024" ]; then
    rm $filename
  fi

  echo -e "Finished download + conversion  $count / $length"
  logger -t pp_client "Finished download + conversion  $count / $length"
