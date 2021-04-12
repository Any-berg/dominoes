#!/bin/bash

error() {
  status=${2:-1}
  >&2 echo "ERROR: $1"
  exit $status
}

# log only the errors that cause Apache HTTP Server to malfunction; did not help
#sed -Ei 's/^(LogLevel) .*/\1 error/g' /usr/local/apache2/conf/httpd.conf

# disable Apache error logging entirely, as it logs everything except errors
sed -Ei "s|^(ErrorLog )(/proc/.*)|\1 \2|g" /usr/local/apache2/conf/httpd.conf

# make sure to kill the test if it doesn't finish within the allotted time 
timeout -s SIGKILL 30 \
  /usr/local/bin/docker-entrypoint.sh agent -dev -client 0.0.0.0 &
status=$?
[ $status -ne 0 ] && error "entrypoint fails to start" $status
entrypoint_pid=$!

# fail if Apache HTTP Server PID file is not created or does not match a process
while true; do
  sleep 1
  httpd_pid=$(cat /usr/local/apache2/logs/httpd.pid 2> /dev/null)
  [[ ! -z "$httpd_pid" ]] && kill -0 $httpd_pid && break
  kill -0 $entrypoint_pid || error "httpd fails to start"
done

# fail if Apache HTTP Server is not behind port 80
curl localhost:80 > /dev/null 2>&1 || error "httpd does not listen on port 80"

# fail if the container does not shut down gracefully after receiving SIGTERM
kill -SIGTERM $entrypoint_pid
wait $entrypoint_pid
status=$?
[ $status -ne 0 ] && error "container does not shut down" $status

# fail if any httpd process outlives the container (i.e. has to be terminated)
ps -o comm | grep httpd > /dev/null && error "httpd is not shut down gracefully"

# make sure to kill the test if it doesn't finish within the allotted time
timeout -s SIGKILL 40 \
  /usr/local/bin/docker-entrypoint.sh agent -dev -client 0.0.0.0 &
status=$?
[ $status -ne 0 ] && error "entrypoint fails to start (2)" $status
entrypoint_pid=$!

# fail if Apache HTTP Server PID file is not created or does not match a process
while true; do
  sleep 1
  httpd_pid=$(cat /usr/local/apache2/logs/httpd.pid 2> /dev/null)
  [[ ! -z "$httpd_pid" ]] && kill -0 $httpd_pid && break
  kill -0 $entrypoint_pid || error "httpd fails to start (2)"
done

# give actual entrypoint some time to spot Apache HTTP Server before stopping it
sleep 2
apachectl -k graceful-stop

wait $entrypoint_pid
status=$?
[ $status -ne 0 ] || error "Consul is not shut down and container is OK with it"

exit 0

# https://unix.stackexchange.com/questions/185283/how-do-i-wait-for-a-file-in-the-shell-script
# https://phoenixnap.com/kb/docker-run-override-entrypoint
# https://stackoverflow.com/questions/58298774/standard-init-linux-go211-exec-user-process-caused-exec-format-error
# https://docs.github.com/en/actions/creating-actions/creating-a-docker-container-action
# https://serverfault.com/questions/607873/apache-is-ok-but-what-is-this-in-error-log-mpm-preforknotice
# https://www.howtogeek.com/423286/how-to-use-the-timeout-command-on-linux/
