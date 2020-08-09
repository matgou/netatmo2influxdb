FROM debian

RUN apt-get update
RUN apt-get install -y ca-certificates curl jq netcat

ADD netatmo2influxdb.sh /

EXPOSE 8080

CMD bash /netatmo2influxdb.sh
