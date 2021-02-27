#!/bin/bash


###############################################################################
# Param
###############################################################################
ficlog=/tmp/log.txt
fictoken=/tmp/token.txt

api_base=https://api.netatmo.com/

###############################################################################
# function
###############################################################################
log() 
{
	echo $(date) $* | tee -a $ficlog
}

send_influx()
{
	data="$1 value=$2"
	log "Send to influx : $data"
	curl -s -u $influxdb_user:$influxdb_password -XPOST "$influxdb_url/write?db=$influxdb_database" --data-binary "$data"
	if [ "$?" != "0" ]
	then
		log "Error influxdb"
	fi
}

refresh_token()
{
  if [ $token_expiration -lt $( date "+%s" ) ]	
  then
    log "Besoin de refresh le token"
    token=$( curl -s -d "grant_type=refresh_token&client_id=$client_id&client_secret=$client_secret&refresh_token=$refresh_token" -X POST -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" $api_base/oauth2/token )
    echo $token > $fictoken
    access_token=$( cat $fictoken | jq -r '.access_token' )
    refresh_token=$( cat $fictoken | jq -r '.refresh_token' )
    expire_in=$( cat $fictoken | jq -r '.expire_in' )
    token_timestamp=$( date "+%s" --date "$( stat --printf '%y\n' /tmp/token.txt )" )
    token_expiration=$(( $token_timestamp + $expire_in ))

  else
    log "Pas besoin de refresh le token"
  fi
}

###############################################################################
# Step 1: display url
###############################################################################
log "go to: $api_base/oauth2/authorize?client_id=$client_id&redirect_uri=$redirect_url&scope=read_thermostat&state=test"

###############################################################################
# Step 2: get tocken with return code
###############################################################################
if [ ! -f $fictoken ]
then
  rm /tmp/http_request
  RESPONSE="HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\nOK\r\n"
  echo -en "$RESPONSE" | nc -q 1 -lp 8080 > /tmp/http_request
  code=$( head -1 /tmp/http_request | sed "s/.*code=//" | sed "s/ .*//" )
  curl_data="grant_type=authorization_code&client_id=$client_id&client_secret=$client_secret&code=$code&redirect_uri=$redirect_url&scope=read_thermostat"
  log $curl_data
  token=$( curl -s -d "grant_type=authorization_code&client_id=$client_id&client_secret=$client_secret&code=$code&redirect_uri=$redirect_url&scope=read_thermostat" -X POST -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" $api_base/oauth2/token )
  log $token
  echo $token > $fictoken
fi
access_token=$( cat $fictoken | jq -r '.access_token' )
[ "$access_token" != "" ] || ( log "invalid token" && rm $fictoken && exit 255 )

refresh_token=$( cat $fictoken | jq -r '.refresh_token' )
expire_in=$( cat $fictoken | jq -r '.expire_in' )
token_timestamp=$( date "+%s" --date "$( stat --printf '%z\n' /tmp/token.txt )" )
token_expiration=$(( $token_timestamp + $expire_in ))

log "token expiration date: $token_timestamp + $expire_in = $(( $token_timestamp + $expire_in ))"


###############################################################################
# Step 3: determine home_id
###############################################################################
data=$( curl -s -H "Authorization: Bearer $access_token" $api_base/api/homesdata )
home_id=$( echo $data | jq  ".body.homes[0].id" | sed 's/"//g' )
log "Utilisation de home_id = $home_id"

###############################################################################
# Step 4: infinite loop
###############################################################################
while `true`
do
	refresh_token
	status=$( curl -s -H "Authorization: Bearer $access_token" https://api.netatmo.net/api/homestatus?home_id=$home_id )
	echo $status > /tmp/status
	nb_rooms=$( echo $status | jq -r '.body.home.rooms' | jq length )
	for i in $( seq 0 $(( $nb_rooms - 1 )) )
	do
		temp=$( echo $status | jq ".body.home.rooms[$i].therm_measured_temperature" )
		consigne=$( echo $status | jq ".body.home.rooms[$i].therm_setpoint_temperature" )
		log "`date`: therm_measured_temperature_$i: $temp"
		send_influx therm_measured_temperature_$i $temp
		log "`date`: therm_setpoint_temperature_$i: $consigne"
		send_influx therm_setpoint_temperature_$i $consigne
	done
	sleep 30
done
