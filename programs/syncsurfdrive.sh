#!/bin/zsh

cd ..
printf "start thumb"
rclone -v sync --no-update-modtime --delete-excluded --exclude '.DS_Store' thumb surfdrive:Shared/Israels-Scans-Curated/thumb
printf "end   thumb"

printf "start scans"
rclone -v sync --no-update-modtime --delete-excluded --exclude '.DS_Store' scans surfdrive:Shared/Israels-Scans-Curated/scans
printf "end   scans"

# printf "start original-backsides"
# rclone -v sync --no-update-modtime --delete-excluded --exclude '.DS_Store' _local/ScansBacksides surfdrive:Shared/Israels-Scans-Curated/original-backsides
# printf "end   original-backsides"

# printf "start original-revisited"
# rclone -v sync --no-update-modtime --delete-excluded --exclude '.DS_Store' _local/ScansOrigRevisited surfdrive:Shared/Israels-Scans-Curated/original-revisited
# printf "end   original-revisited"

# printf "start original"
# rclone -v sync --no-update-modtime --delete-excluded --exclude '.DS_Store' _local/ScansOrig surfdrive:Shared/Israels-Scans-Curated/original
# printf "end   original"
