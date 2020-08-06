#!/usr/bin/dumb-init /bin/sh
#set -e

# start Consul in the background (agent -retry-join lb -client=0.0.0.0)
consul-entrypoint.sh "$@" &
consul_pid=$!

# setup Apache HTTP Server to eliminate warning & distinguish between instances
sed -Ei 's/#(ServerName) .*/\1 localhost/g' /usr/local/apache2/conf/httpd.conf
sed -i "s/It works!/$HOSTNAME/g" /usr/local/apache2/htdocs/index.html

# start Apache HTTP Server as daemon 
rm -f /usr/local/apache2/logs/httpd.pid
httpd
status=$?
[ $status -ne 0 ] && { echo "Apache HTTP Server failed"; exit $status; }
while true; do
  sleep 1
  httpd_pid=$(cat /usr/local/apache2/logs/httpd.pid 2> /dev/null)
  [[ ! -z "$httpd_pid" ]] && kill -0 $httpd_pid && break
done

# while Apache HTTP Server is running, check on Consul and stop Apache if needed
while [ -d "/proc/$httpd_pid" ]; do
    [ -d "/proc/$consul_pid" ] || apachectl -k graceful-stop
    sleep 5
done # stop Docker container gracefully

# https://docs.docker.com/config/containers/multi-service_container/
# https://stackoverflow.com/questions/1908610/how-to-get-process-id-of-background-process
# https://askubuntu.com/questions/256013/apache-error-could-not-reliably-determine-the-servers-fully-qualified-domain-n
