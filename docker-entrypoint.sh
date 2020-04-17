#!/bin/bash

# Starts Consul Agent in Dev Mode
consul agent \
 -dev \
 -datacenter="dc1" \
 -data-dir="/home/deploy/consul/consul-data" \
 -server=true \
 -client="0.0.0.0" \
 -ui=true \
 -bind='{{GetInterfaceIP "eth0"}}' \
 -log-level="err"
