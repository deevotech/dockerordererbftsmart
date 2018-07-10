#!/bin/bash
sudo rm -rf data/*
mkdir -p data
mkdir data/logs
sudo rm -rf setup/*
#while [ ! -f /data/logs/frontend-0.success ] || [ ! -f /data/logs/peer1-org1.success ] || [ ! -f /data/logs/peer1-org2.success ] || [ ! -f /data/logs/peer2-org1.success ] || [ ! -f /data/logs/peer2-org2.success ] ; do
#    sleep 2
#done
set -e

SDIR=$(dirname "$0")
source ${SDIR}/scripts/env.sh

cd ${SDIR}

# Delete docker containers
dockerContainers=$(docker ps -a | awk '$2~/hyperledger/ {print $1}')
if [ "$dockerContainers" != "" ]; then
   log "Deleting existing docker containers ..."
   docker rm -f $dockerContainers > /dev/null
fi

# Remove chaincode docker images
chaincodeImages=`docker images | grep "^dev-peer" | awk '{print $3}'`
if [ "$chaincodeImages" != "" ]; then
   log "Removing chaincode docker images ..."
   docker rmi -f $chaincodeImages > /dev/null
fi