#!/bin/bash

while [ 1 ]; do
    SERVERD_CONFIG="/home/ec2-user/auto-tester.puremagic.com/config.json" ./obj/update-pulls-prod
    sleep 10m
done
