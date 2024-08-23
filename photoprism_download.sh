#!/bin/bash

# PhotoPrisn Server configuration
base_url="http://server/photos"
base_url_dl="http://server"

# Credentials
username="username"
password="password"

# FTP Upload
ftp_host="host"
ftp_user="username"
ftp_pw="password"
ftp_limit=2M

# Ourput image format
image_format="heic"

# Primary/secondary image processor - Primary does all the work and uploads to FTP / secondary only waits and donloads from FTP
primary_proc=1

#Set parallel running jobs
parallel_jobs=1

# Read Credentials and Server config from env file
source photoprism_download.env

#echo -e "$base_url\n$base_url_dl\n$username\n$password"

# Current date
day="$(date +%d)"
month="$(date +%m)"

# Read last run date
touch photoprism_download.run
day_run=""
month_run=""
source photoprism_download.run

if [ "$day" == "$day_run" ] && [ "$month" == "$month_run" ]
then
  echo "Photos download already ran"
  logger -t pp_client "Photos download already ran"
  exit 0
fi

mkdir -p images
mkdir -p movies

# Remove previous files
yesterday=$(date -d "yesterday 13:00" '+%m-%d')
rm -f images/*$yesterday*
rm -f movies/*$yesterday*


if (( $primary_proc ))
then

  echo "Starting photos download"
  # Creating Session
  response=$(curl -s -H "Content-Type: application/json" -d '{"username": "'$username'", "password": "'$password'"}' $base_url"/api/v1/session")
  session_id=$(echo $response | jq -r ".id")

  # Find Images
  #images=$(curl -s $base_url"/api/v1/photos/view?count=720&offset=0&merged=true&country=&camera=2&lens=0&label=&year=0&month=0&color=&order=newest&q=&public=tr>
  images=$(curl -s $base_url"/api/v1/photos/view?count=9999&year=&month=$month&day=$day&order=oldest" \
    -H "X-Session-ID: "$session_id)

  # Prepare Images download
  images_dl+=($(echo $images | jq -r ".[].DownloadUrl"))
  images_date+=($(echo $images | jq -r ".[].TakenAtLocal"))

  # Primary procesor - Get Images from PhotoPrism
  length=$(printf "%03d" ${#images_dl[@]})
  logger -t pp_client "Starting $length images download and conversion"

  #for i in {0..2}; do
  for i in ${!images_dl[@]}; do
    (
      printf -v count "%03d" "$((i+1))"
      ./photoprism_download_worker.sh $count $length $base_url_dl ${images_dl[$i]} ${images_date[$i]} $image_format
    ) &

    # allow to execute up to $parallel_jobs jobs in parallel
    if [[ $(jobs -r -p | wc -l) -ge $parallel_jobs ]]; then
      # now there are $parallel_jobs jobs already running, so wait here for any job to be finished so there is a place to start next one.
      wait -n
    fi
  done

  # no more jobs to be started but wait for pending jobs (all need to be finished)
  wait

  # Upload to central server for all PIs
  logger -t pp_client "Starting FTP upload $length images and movies"
  cd images
  for filename in *; do
    curl -s -S --ftp-create-dirs --limit-rate $ftp_limit -T $filename ftp://$ftp_user:$ftp_pw@$ftp_host/pp_pictures/$month/images-$month$day/
  done
  cd ..
  if [ -n "$(ls -A movies)" ]; then
    cd movies
    for filename in *; do
      curl -s -S --ftp-create-dirs --limit-rate $ftp_limit -T $filename ftp://$ftp_user:$ftp_pw@$ftp_host/pp_pictures/$month/movies-$month$day/
    done
    cd ..
  fi
  # Add .finished file for secondary processors
  echo -n "" | curl -s -S --ftp-create-dirs --limit-rate $ftp_limit -T - ftp://$ftp_user:$ftp_pw@$ftp_host/pp_pictures/$month/images-$month$day/.finished
  logger -t pp_client "Finished FTP upload $length images and movies"

  echo "Finished $length images download, conversion and upload"
  logger -t pp_client "Finished $length images download, conversion and upload"

#Secondary processor
else
  echo "Starting downloading from FTP"
  logger -t pp_client "Starting downloading from FTP"
  cd images
  # wait max 2.5 hours ( 300 secs * 30 retries ) for last image to appear on FTP
  echo "Waiting for files on FTP - ignore curl warnings"
  curl -s -S --retry-all-errors --retry-delay 300 --retry 30 --limit-rate $ftp_limit ftp://$ftp_user:$ftp_pw@$ftp_host/pp_pictures/$month/images-$month$day/.finished
  # download all images
  echo "FTP is ready: start real downloading"
  wget -q --limit-rate $ftp_limit ftp://$ftp_user:$ftp_pw@$ftp_host/pp_pictures/$month/images-$month$day/*
  rm .finished
  cd ..
  cd movies
  wget -q --limit-rate $ftp_limit ftp://$ftp_user:$ftp_pw@$ftp_host/pp_pictures/$month/movies-$month$day/*
  cd ..
  echo "Finished downloading from FTP"
  logger -t pp_client "Finished downloading from FTP"
fi

if [ -z "$(ls -A images)" ]; then
  # Empty images
  logger  -t pp_client "No images downloaded. Something is wrong"
  exit 1
else
  # Save last run date
  echo -e "day_run=$day\nmonth_run=$month" > photoprism_download.run
fi
