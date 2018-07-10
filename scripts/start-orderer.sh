#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
set -e

source $(dirname "$0")/env.sh

# Wait for setup to complete sucessfully
awaitSetup

# Enroll to get orderer's TLS cert (using the "tls" profile)
fabric-ca-client enroll -d --enrollment.profile tls -u $ENROLLMENT_URL -M /tmp/tls --csr.hosts $ORDERER_HOST

# Copy the TLS key and cert to the appropriate place
TLSDIR=$ORDERER_HOME/tls
mkdir -p $TLSDIR
cp /tmp/tls/keystore/* $ORDERER_GENERAL_TLS_PRIVATEKEY
cp /tmp/tls/signcerts/* $ORDERER_GENERAL_TLS_CERTIFICATE
rm -rf /tmp/tls

# Enroll again to get the orderer's enrollment certificate (default profile)
fabric-ca-client enroll -d -u $ENROLLMENT_URL -M $ORDERER_GENERAL_LOCALMSPDIR

# Finish setting up the local MSP for the orderer
finishMSPSetup $ORDERER_GENERAL_LOCALMSPDIR
copyAdminCert $ORDERER_GENERAL_LOCALMSPDIR
mkdir -p /data/orderer
cp -R /etc/hyperledger/orderer/* /data/orderer/
# Wait for the genesis block to be created

cd /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1
if [ -f ./config/currentView ]; then
rm -f ./config/currentView
fi
# get ip host
HOST_IP=$(hostname -I)
echo "
0 127.0.0.1 11000
1 127.0.0.1 11010
2 127.0.0.1 11020
3 127.0.0.1 11030
" > /data/hosts.config

KEYFILE=""
SIGN_FILE=""
for entry in `ls /data/orgs/org0/admin/msp/keystore/`; do
    KEYFILE=${entry}
done
for entry in `ls /data/orgs/org0/admin/msp/signcerts/`; do
    SIGN_FILE=${entry}
done
cat /data/hosts.config > /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/hosts.config
cat /data/node.config > /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/node.config

cat /data/orgs/org0/admin/msp/keystore/$KEYFILE > /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/key.pem
cat /data/orgs/org0/admin/msp/signcerts/$SIGN_FILE > /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/peer.pem
#cat /data/orderer/msp/keystore/$KEYFILE > /data/key.pem
#cat /data/orderer/msp/signcerts/$SIGN_FILE > /data/peer.pem
#cat /data/key.pem > /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/key.pem
#cat /data/peer.pem > /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/peer.pem
# ./startFrontend.sh 1000 10 9999 &>/data/logs/frontend.logs
# start replica

./startReplica.sh 0 > /data/logs/replica-0.success 2>&1 &

sleep 2
./startReplica.sh 1 > /data/logs/replica-1.success 2>&1 &

sleep 2

./startReplica.sh 2 > /data/logs/replica-2.success 2>&1 &
sleep 2

./startReplica.sh 3 > /data/logs/replica-3.success 2>&1 &

while [ ! -f /data/logs/replica-0.success ] || [ ! -f /data/logs/replica-1.success ] || [ ! -f /data/logs/replica-2.success ] || [ ! -f /data/logs/replica-3.success ] ; do
 sleep 2
done
# start frontend
./startFrontend.sh 1000 10 9999 > /data/logs/frontend-0.success 2>&1 &
sleep 5
#dowait "genesis block to be created" 60 $SETUP_LOGFILE $ORDERER_GENERAL_GENESISFILE
while [ ! -f /data/logs/frontend-0.success ] ; do
 sleep 2
done
# Start the orderer
env | grep ORDERER > /data/orderer.config
env | grep ORDERER
export FABRIC_CA_DYNAMIC_LINK=true
FABRIC_CFG_PATH=/etc/hyperledger/fabric
ls -la $FABRIC_CFG_PATH/* > /data/list-orderer.txt
orderer
