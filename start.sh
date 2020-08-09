#!/bin/bash
docker run \
  -e client_id=################ \
  -e client_secret=################ \
  -e client_username=################ \
  -e client_password=################ \
  -e influxdb_url=################ \
  -e influxdb_database=################ \
  -e influxdb_user=################ \
  -e influxdb_password=################ \
  -e redirect_url=################ \
  -p 8080:8080 \
  netatmo2influxdb
