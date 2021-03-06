#!/bin/bash
set -e
source $(dirname "$0")/env.sh
awaitSetup
while [ ! -f /data/key.pem ] ; do
	sleep 2 
done
cd /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1
if [ -f ./config/currentView ]; then
rm -f ./config/currentView
fi
cat /data/hosts.config > /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/hosts.config
cat /data/node.config > /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/node.config
cat /data/key.pem > /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/key.pem
cat /data/peer.pem > /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/peer.pem
echo "finish copy" > /data/logs/replica-$NUMBER.success
./startReplica.sh $NUMBER
