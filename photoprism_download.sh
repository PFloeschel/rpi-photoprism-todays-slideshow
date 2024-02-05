#!/bin/bash

# PhotoPrisn Server configuration
base_url="http://server/photos"
base_url_dl="http://server"

# Credentials
username="username"
password="password"

# Read Credentials and Server config from env file
source photoprism_download.env

#echo -e "$base_url\n$base_url_dl\n$username\n$password"

# Current date
day=$(date +%d)
month=$(date +%m)

# Last run date
touch last_run
day_run=$(awk '{print $1}' last_run)
month_run=$(awk '{print $2}' last_run)

if (( day == day_run  )) && (( month == month_run ))
then
  echo "Photos download already ran"
  logger -t pp_client "Photos download already ran"
  exit 0
fi

echo "Starting photos download"

# Creating Session
response=$(curl -s -H "Content-Type: application/json" -d '{"username": "'$username'", "password": "'$password'"}' $base_url"/api/v1/session")
session_id=$(echo $response | jq -r ".id")

# Find Images
#images=$(curl -s $base_url"/api/v1/photos/view?count=720&offset=0&merged=true&country=&camera=2&lens=0&label=&year=0&month=0&color=&order=newest&q=&public=tr>
images=$(curl -s $base_url"/api/v1/photos/view?count=999&year=&month=$month&day=$day&order=oldest" \
  -H "X-Session-ID: "$session_id)

#echo $images | jq '.'

# Prepare Images download
#images_id+=($(echo $images | jq -r ".[].UID"))
images_dl+=($(echo $images | jq -r ".[].DownloadUrl"))
images_date+=($(echo $images | jq -r ".[].TakenAtLocal"))
mkdir -p images

# Download Images
length=$(printf "%03d" ${#images_dl[@]})
logger -t pp_client "Starting $length images download and conversion"
for i in ${!images_dl[@]}; do
  printf -v count "%03d" "$((i+1))"
  sem --id pp_client -j+0 ./photoprism_download_worker.sh $count $length $base_url_dl ${images_dl[$i]} ${images_date[$i]}
done
sem --id pp_client --wait

echo "Finished $length images download and conversion"
logger -t pp_client "Finished $length images download and conversion"

# Remove previous files
yesterday=$(date -d "yesterday 13:00" '+%m-%d')
yesterday2=$(date -d "yesterday -1 day 13:00" '+%m-%d')
rm -f images/*$yesterday*

# Save last run date
echo "$day $month" > last_run
