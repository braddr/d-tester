#!/bin/bash

while [ 1 ]; do
    PATH_INFO="/test-results/addv2/update_pulls" REMOTE_ADDR="192.168.10.156" ./serverd-prod
    sleep 10m
done
