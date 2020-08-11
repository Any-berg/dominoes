#!/usr/bin/dumb-init /bin/sh
#set -e

# start Consul in the background (agent -retry-join lb -client=0.0.0.0)
consul-entrypoint.sh "$@" &
consul_pid=$!

# prevent exit code 143 and let SIGTERM pass to Consul
trap '' SIGTERM

# setup Apache HTTP Server to identify instances & hide warning about ServerName
sed -i "s/It works!/$HOSTNAME/g" /usr/local/apache2/htdocs/index.html
conf="/usr/local/apache2/conf/httpd.conf"
sed -Ei 's/#(ServerName) .*/\1 localhost/g' $conf

# redirect Apache HTTP Server logging back to stdout and stderr through symlinks
sed -Ei "s|^(ErrorLog )/proc/.*|\1/usr/local/apache2/logs/error.log|g" $conf
sed -Ei "s|^(\s+CustomLog ).*|\1/usr/local/apache2/logs/access.log combined|g" $conf
ln -sf /proc/$$/fd/1 /usr/local/apache2/logs/access.log
ln -sf /proc/$$/fd/2 /usr/local/apache2/logs/error.log

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
    sleep 2
done

# ensure that Consul was really shut down before Apache HTTP Server
[[ ! -d "/proc/$consul_pid" ]] || exit 1

# https://docs.docker.com/config/containers/multi-service_container/
# https://stackoverflow.com/questions/1908610/how-to-get-process-id-of-background-process
# https://askubuntu.com/questions/256013/apache-error-could-not-reliably-determine-the-servers-fully-qualified-domain-n
# https://stackoverflow.com/questions/40263585/redirecting-apache-logs-to-stdout
# https://hackernoon.com/my-process-became-pid-1-and-now-signals-behave-strangely-b05c52cc551c
# https://medium.com/better-programming/understanding-docker-container-exit-codes-5ee79a1d58f6
