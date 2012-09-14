#!/bin/bash

while [ 1 ]; do
    SERVERD_CONFIG="/home/braddr/sandbox/d/d-tester/serverd/config.json" ./update-pulls-prod
    sleep 10m
done
