#!/bin/bash

error() {
  status=${2:-1}
  >&2 echo "ERROR: $1"
  exit $status
}

# set 30s timebox for testing (to avoid getting stuck in an infinite while loop)
timeout 30 /usr/local/bin/docker-entrypoint.sh agent -dev -client 0.0.0.0 &
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

# fail if there is no Consul process to shut down gracefully (race condition?)
#consul_pid=$(ps -o pid,user | grep consul$ | xargs | cut -d ' ' -f 1)
consul leave || error "consul fails"
#kill -SIGUSR2 $entrypoint_pid

# fail if container exits with a status code other than 0
wait $entrypoint_pid
status=$?
[ $status -ne 0 ] && error "container does not shut down" $status

# fail if any httpd process outlives the container (i.e. has to be terminated)
ps -o comm | grep httpd > /dev/null && error "httpd is not shut down gracefully"

# exit without errors (above grep should fail and its status mustn't be passed on) 
exit 0

>>>>>>> Stashed changes
# https://unix.stackexchange.com/questions/185283/how-do-i-wait-for-a-file-in-the-shell-script
# https://phoenixnap.com/kb/docker-run-override-entrypoint
# https://stackoverflow.com/questions/58298774/standard-init-linux-go211-exec-user-process-caused-exec-format-error
# https://docs.github.com/en/actions/creating-actions/creating-a-docker-container-action
