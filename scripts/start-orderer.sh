#!/bin/bash
cd /opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1
./startFrontend.sh 1000 10 9999
orderer start
