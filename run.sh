#!/bin/bash

# Start Container Image
CONTAINER_CHECK=($(docker inspect hashi-resume -f '{{.State.Running}}' > /dev/null 2>&1 && echo true || echo false))

if [[ "${CONTAINER_CHECK}" != *"true"* ]]; then
  echo "Starting Container..."
  docker run -dt --rm \
   -p 8500:8500 \
   -e "FULL_NAME=$1" \
   --name hashi-resume \
   hashi-resume:latest

  sleep 2
  
  echo "Running Fixtures Script..."
  docker exec hashi-resume /bin/sh -c "source ./fixtures.sh $1"

elif [[ "${CONTAINER_CHECK}" == *"true"* ]]; then
  echo "Container is Already Running..."
  docker exec hashi-resume /bin/sh -c "consul kv get --recurse $1 | grep -i $1 > /dev/null 2>&1 && echo 'Fixtures Already Exist...' || source ./fixtures.sh $1"

fi


# Render and Print Resume
docker exec -it hashi-resume /bin/sh -c "export FULL_NAME=$1; consul-template -log-level=info -template='resume.ctmpl:resume.txt' -once"
docker exec -it hashi-resume cat resume.txt

sleep 3

# Open Consul's Key/Value Page
open http://localhost:8500/ui/dc1/kv
