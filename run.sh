#!/bin/bash

# Start Container Image
CONTAINER_CHECK=($(docker inspect hashi-resume -f '{{.State.Running}}' > /dev/null 2>&1 &&  echo true || echo false))
if [[ "${CONTAINER_CHECK}" != *"true"* ]]; then
  echo "Starting Container..."
  docker run -dt --rm \
   -p 8500:8500 \
   -e "FULL_NAME=$1" \
   --name hashi-resume \
   hashi-resume:latest

  sleep 2
fi


# Populate Consul with Data
consul kv put "$1/address" "1234 Seaseme Street, Somewhere, CA. 12345"
consul kv put "$1/email" "someone@mydomain.com"
consul kv put "$1/phone" "123-456-7890"
consul kv put "$1/profile_summary" "Looking to work with modern technologies!"

consul kv put "$1/org/0/name" "GreatCall, Inc."
consul kv put "$1/org/0/position/0/name" "CloudOps Engineer"
consul kv put "$1/org/0/position/0/tasks/0" "I did a bunch of things."
consul kv put "$1/org/0/position/0/tasks/1" "Like more time I spent there, I did more"
consul kv put "$1/org/0/position/0/tasks/2" "I was very productive at times."
consul kv put "$1/org/0/position/1/name" "Sr. CloudOps Engineer"
consul kv put "$1/org/0/position/1/tasks/0" "I did a bunch more things."
consul kv put "$1/org/0/position/1/tasks/1" "Seemed like I was there forever."
consul kv put "$1/org/0/position/1/tasks/2" "I over stayed my welcome."
consul kv put "$1/org/0/position/2/name" "Principal Cloud Engineer"
consul kv put "$1/org/0/position/2/tasks/0" "So I continued to do more."
consul kv put "$1/org/0/position/2/tasks/1" "I really needed a vacation."
consul kv put "$1/org/0/position/2/tasks/2" "Not to mention a nice bonus."

consul kv put "$1/org/1/name" "Dexcom, Inc."
consul kv put "$1/org/1/position/0/name" "DevOps Engineer"
consul kv put "$1/org/1/position/0/tasks/0" "I did a bunch of things."
consul kv put "$1/org/1/position/0/tasks/1" "Like more time I spent there, I did more"
consul kv put "$1/org/1/position/0/tasks/2" "I was very productive at times."
consul kv put "$1/org/1/position/1/name" "Sr. DevOps Engineer"
consul kv put "$1/org/1/position/1/tasks/0" "I did a bunch more things."
consul kv put "$1/org/1/position/1/tasks/1" "Seemed like I was there forever."
consul kv put "$1/org/1/position/1/tasks/2" "I over stayed my welcome."
consul kv put "$1/org/1/position/2/name" "Principal Software Engineer"
consul kv put "$1/org/1/position/2/tasks/0" "So I continued to do more."
consul kv put "$1/org/1/position/2/tasks/1" "I really needed a vacation."
consul kv put "$1/org/1/position/2/tasks/2" "Not to mention a nice bonus."

# Render and Print Resume
docker exec -it hashi-resume consul-template -log-level=info -template='/home/deploy/resume.ctmpl:/home/deploy/resume.txt' -once
docker exec -ti hashi-resume cat /home/deploy/resume.txt