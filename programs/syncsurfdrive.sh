#!/bin/zsh

cd ..
# rclone -v sync --no-update-modtime --delete-excluded --exclude '.DS_Store' scans surfdrive:Israels-Scans-Curated/jpg
rclone -v sync --no-update-modtime --delete-excluded --exclude '.DS_Store' _local/ScansOrig surfdrive:Israels-Scans-Curated/original
rclone -v sync --no-update-modtime --delete-excluded --exclude '.DS_Store' _local/ScansOrigRevisited surfdrive:Israels-Scans-Curated/original-revisited
# rclone -v sync --no-update-modtime  --delete-excluded --exclude '.DS_Store' curatedscans surfdrive:Translatin-Sources-Scans
