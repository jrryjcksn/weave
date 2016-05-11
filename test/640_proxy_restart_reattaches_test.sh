#! /bin/bash

. ./config.sh

NAME=seetwo.weave.local

check_attached() {
    assert_raises "exec_on $HOST1 c2 $CHECK_ETHWE_UP"
    assert_dns_record $HOST1 c1 $NAME $C2
}

N=50
# Create and remove a lot of containers in a small subnet; the failure
# mode is that this takes a long time as it has to wait for the old
# ones to time out, so we run this function inside 'timeout'
run_many() {
    for i in $(seq $N); do
        proxy docker_on $HOST1 run -e WEAVE_CIDR=net:10.32.4.0/28 --rm -t $SMALL_IMAGE /bin/true
    done
}

start_suite "Proxy restart reattaches networking to containers"

weave_on $HOST1 launch
proxy_start_container          $HOST1 -di --name=c2 --restart=always -h $NAME
proxy_start_container_with_dns $HOST1 -di --name=c1 --restart=always
C2=$(container_ip $HOST1 c2)

proxy docker_on $HOST1 restart -t=1 c2
check_attached

# Restart weave router
docker_on $HOST1 restart weave
sleep 1
check_attached

# Kill outside of Docker so Docker will restart it
run_on $HOST1 sudo kill -KILL $(docker_on $HOST1 inspect --format='{{.State.Pid}}' c2)
sleep 1
check_attached

run_on $HOST1 "sudo service docker restart"
wait_for_proxy $HOST1
sleep 5 # allow for re-tries of attach
# Re-fetch the IP since it is not retained on docker restart
C2=$(container_ip $HOST1 c2) || (echo "container c2 has no IP address" 2>&1; exit 1)
check_attached

assert_raises "timeout 90 cat <( run_many )"

# Start a container that needs IPAM, then restart it when the router is stopped
proxy_start_container $HOST1 -di --name=c3 --restart=always
assert_raises "exec_on $HOST1 c3 $CHECK_ETHWE_UP"
weave_on $HOST1 stop-router
docker_on $HOST1 restart c3
weave_on $HOST1 launch-router
sleep 5
assert_raises "exec_on $HOST1 c3 $CHECK_ETHWE_UP"

# Restarting proxy shouldn't kill unattachable containers
weave_on $HOST1 stop
weave_on $HOST1 launch-proxy
assert_raises "exec_on $HOST1 c3 $CHECK_ETHWE_UP"

end_suite
