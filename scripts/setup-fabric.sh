#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# This script does the following:
# 1) registers orderer and peer identities with intermediate fabric-ca-servers
# 2) Builds the channel artifacts (e.g. genesis block, etc)
#

function main {
   log "Beginning building channel artifacts ..."
   registerIdentities
   getCACerts
   makeConfigTxYaml
   generateChannelArtifacts
   log "Finished building channel artifacts"
   generateBftConfig
   touch /$SETUP_SUCCESS_FILE
}

# Enroll the CA administrator
function enrollCAAdmin {
   waitPort "$CA_NAME to start" 90 $CA_LOGFILE $CA_HOST 7054
   log "Enrolling with $CA_NAME as bootstrap identity ..."
   export FABRIC_CA_CLIENT_HOME=$HOME/cas/$CA_NAME
   export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
   fabric-ca-client enroll -d -u https://$CA_ADMIN_USER_PASS@$CA_HOST:7054
}

function registerIdentities {
   log "Registering identities ..."
   registerOrdererIdentities
   registerPeerIdentities
}

# Register any identities associated with the orderer
function registerOrdererIdentities {
   for ORG in $ORDERER_ORGS; do
      initOrgVars $ORG
      enrollCAAdmin
      local COUNT=1
      while [[ "$COUNT" -le $NUM_ORDERERS ]]; do
         initOrdererVars $ORG $COUNT
         log "Registering $ORDERER_NAME with $CA_NAME"
         fabric-ca-client register -d --id.name $ORDERER_NAME --id.secret $ORDERER_PASS --id.type orderer
         COUNT=$((COUNT+1))
      done
      log "Registering admin identity with $CA_NAME"
      # The admin identity has the "admin" attribute which is added to ECert by default
      fabric-ca-client register -d --id.name $ADMIN_NAME --id.secret $ADMIN_PASS --id.attrs "admin=true:ecert"
   done
}

# Register any identities associated with a peer
function registerPeerIdentities {
   for ORG in $PEER_ORGS; do
      initOrgVars $ORG
      enrollCAAdmin
      local COUNT=1
      while [[ "$COUNT" -le $NUM_PEERS ]]; do
         initPeerVars $ORG $COUNT
         log "Registering $PEER_NAME with $CA_NAME"
         fabric-ca-client register -d --id.name $PEER_NAME --id.secret $PEER_PASS --id.type peer
         COUNT=$((COUNT+1))
      done
      log "Registering admin identity with $CA_NAME"
      # The admin identity has the "admin" attribute which is added to ECert by default
      fabric-ca-client register -d --id.name $ADMIN_NAME --id.secret $ADMIN_PASS --id.attrs "hf.Registrar.Roles=client,hf.Registrar.Attributes=*,hf.Revoker=true,hf.GenCRL=true,admin=true:ecert,abac.init=true:ecert"
      log "Registering user identity with $CA_NAME"
      fabric-ca-client register -d --id.name $USER_NAME --id.secret $USER_PASS
   done
}

function getCACerts {
   log "Getting CA certificates ..."
   for ORG in $ORGS; do
      initOrgVars $ORG
      log "Getting CA certs for organization $ORG and storing in $ORG_MSP_DIR"
      export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
      fabric-ca-client getcacert -d -u https://$CA_HOST:7054 -M $ORG_MSP_DIR
      finishMSPSetup $ORG_MSP_DIR
      # If ADMINCERTS is true, we need to enroll the admin now to populate the admincerts directory
      if [ $ADMINCERTS ]; then
         switchToAdminIdentity
      fi
   done
}

# printOrg
function printOrg {
   echo "
  - &$ORG_CONTAINER_NAME

    Name: $ORG

    # ID to load the MSP definition as
    ID: $ORG_MSP_ID

    # MSPDir is the filesystem path which contains the MSP configuration
    MSPDir: $ORG_MSP_DIR"
}

# printOrdererOrg <ORG>
function printOrdererOrg {
   initOrgVars $1
   printOrg
}

# printPeerOrg <ORG> <COUNT>
function printPeerOrg {
   initPeerVars $1 $2
   printOrg
   echo "
    AnchorPeers:
       # AnchorPeers defines the location of peers which can be used
       # for cross org gossip communication.  Note, this value is only
       # encoded in the genesis block in the Application section context
       - Host: $PEER_HOST
         Port: 7051"
}

function makeConfigTxYaml {
   {
   echo "# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

---
################################################################################
#
#   PROFILES
#
#   Different configuration profiles may be encoded here to be specified as
#   parameters to the configtxgen tool. The profiles which specify consortiums
#   are to be used for generating the orderer genesis block. With the correct
#   consortium members defined in the orderer genesis block, channel creation
#   requests may be generated with only the org member names and a consortium
#   name.
#
################################################################################
Profiles:

    # JCS: my profile
    # SampleSingleMSPBFTsmart defines a configuration which uses the Solo orderer,
    # and contains a single MSP definition (the MSP sampleconfig).
    # The Consortium SampleConsortium has only a single member, SampleOrg
    SampleSingleMSPBFTsmart:
        Orderer:
            <<: *OrdererDefaults
            OrdererType: bftsmart
            Organizations:
                - *org0
        Consortiums:
            SampleConsortium:
                Organizations:
                    - *org1
                    - *org2


    # SampleSingleMSPChannel defines a channel with only the sample org as a
    # member. It is designed to be used in conjunction with SampleSingleMSPSolo
    # and SampleSingleMSPKafka orderer profiles.
    SampleSingleMSPChannel:
        Consortium: SampleConsortium
        Application:
            <<: *ApplicationDefaults
            Organizations:
                - *org1
                - *org2

################################################################################
#
#   ORGANIZATIONS
#
#   This section defines the organizational identities that can be referenced
#   in the configuration profiles.
#
################################################################################
Organizations:
    - &org0
        # Name is the key by which this org will be referenced in channel
        # configuration transactions.
        # Name can include alphanumeric characters as well as dots and dashes.
        Name: org0

        # ID is the key by which this org's MSP definition will be referenced.
        # ID can include alphanumeric characters as well as dots and dashes.
        ID: org0MSP

        # MSPDir is the filesystem path which contains the MSP configuration.
        MSPDir: /data/orgs/org0/msp

    - &org1
        # Name is the key by which this org will be referenced in channel
        # configuration transactions.
        # Name can include alphanumeric characters as well as dots and dashes.
        Name: org1

        # ID is the key by which this org's MSP definition will be referenced.
        # ID can include alphanumeric characters as well as dots and dashes.
        ID: org1MSP

        # MSPDir is the filesystem path which contains the MSP configuration.
        MSPDir: /data/orgs/org1/msp

        # AnchorPeers defines the location of peers which can be used for
        # cross-org gossip communication. Note, this value is only encoded in
        # the genesis block in the Application section context.
        AnchorPeers:
            - Host: peer1-org1
              Port: 7051
    - &org2
        # Name is the key by which this org will be referenced in channel
        # configuration transactions.
        # Name can include alphanumeric characters as well as dots and dashes.
        Name: org2

        # ID is the key by which this org's MSP definition will be referenced.
        # ID can include alphanumeric characters as well as dots and dashes.
        ID: org2MSP

        # MSPDir is the filesystem path which contains the MSP configuration.
        MSPDir: /data/orgs/org2/msp

        # AnchorPeers defines the location of peers which can be used for
        # cross-org gossip communication. Note, this value is only encoded in
        # the genesis block in the Application section context.
        AnchorPeers:
            - Host: peer1-org2
              Port: 7051
################################################################################
#
#   ORDERER
#
#   This section defines the values to encode into a config transaction or
#   genesis block for orderer related parameters.
#
################################################################################
Orderer: &OrdererDefaults

    # Orderer Type: The orderer implementation to start.
    # Available types are "solo" and "kafka".
    OrdererType: bftsmart
    
    # Addresses here is a nonexhaustive list of orderers the peers and clients can 
    # connect to. Adding/removing nodes from this list has no impact on their 
    # participation in ordering. 
    # NOTE: In the solo case, this should be a one-item list.
    Addresses:
        - orderer1-org0:7050

    # Batch Timeout: The amount of time to wait before creating a batch.
    BatchTimeout: 2s

    # Batch Size: Controls the number of messages batched into a block.
    BatchSize:

        # Max Message Count: The maximum number of messages to permit in a
        # batch.
        MaxMessageCount: 10

        # Absolute Max Bytes: The absolute maximum number of bytes allowed for
        # the serialized messages in a batch. If the "kafka" OrdererType is
        # selected, set 'message.max.bytes' and 'replica.fetch.max.bytes' on
        # the Kafka brokers to a value that is larger than this one.
        AbsoluteMaxBytes: 10 MB

        # Preferred Max Bytes: The preferred maximum number of bytes allowed
        # for the serialized messages in a batch. A message larger than the
        # preferred max bytes will result in a batch larger than preferred max
        # bytes.
        PreferredMaxBytes: 512 KB

    # Max Channels is the maximum number of channels to allow on the ordering
    # network. When set to 0, this implies no maximum number of channels.
    MaxChannels: 0

    #JCS: BFT-SMaRt options
    BFTsmart:

        # ConnectionPoolSize: The size of the connection pool that links the golang component to the java component.
        ConnectionPoolSize: 10

        # RecvPort: The localhost TCP port from which the java component sends blocks to the golang component.
        RecvPort: 9999

    # Organizations lists the orgs participating on the orderer side of the
    # network.
    Organizations:

################################################################################
#
#   APPLICATION
#
#   This section defines the values to encode into a config transaction or
#   genesis block for application-related parameters.
#
################################################################################
Application: &ApplicationDefaults

    # Organizations lists the orgs participating on the application side of the
    # network.
    Organizations:

################################################################################
#
#   CAPABILITIES
#
#   This section defines the capabilities of fabric network. This is a new
#   concept as of v1.1.0 and should not be utilized in mixed networks with
#   v1.0.x peers and orderers.  Capabilities define features which must be
#   present in a fabric binary for that binary to safely participate in the
#   fabric network.  For instance, if a new MSP type is added, newer binaries
#   might recognize and validate the signatures from this type, while older
#   binaries without this support would be unable to validate those
#   transactions.  This could lead to different versions of the fabric binaries
#   having different world states.  Instead, defining a capability for a channel
#   informs those binaries without this capability that they must cease
#   processing transactions until they have been upgraded.  For v1.0.x if any
#   capabilities are defined (including a map with all capabilities turned off)
#   then the v1.0.x peer will deliberately crash.
#
################################################################################
Capabilities:
    # Channel capabilities apply to both the orderers and the peers and must be
    # supported by both.  Set the value of the capability to true to require it.
    Channel: &ChannelCapabilities
        # V1.1 for Channel is a catchall flag for behavior which has been
        # determined to be desired for all orderers and peers running v1.0.x,
        # but the modification of which would cause incompatibilities.  Users
        # should leave this flag set to true.
        V1_1: true

    # Orderer capabilities apply only to the orderers, and may be safely
    # manipulated without concern for upgrading peers.  Set the value of the
    # capability to true to require it.
    Orderer: &OrdererCapabilities
        # V1.1 for Order is a catchall flag for behavior which has been
        # determined to be desired for all orderers running v1.0.x, but the
        # modification of which  would cause incompatibilities.  Users should
        # leave this flag set to true.
        V1_1: true

    # Application capabilities apply only to the peer network, and may be
    # safely manipulated without concern for upgrading orderers.  Set the value
    # of the capability to true to require it.
    Application: &ApplicationCapabilities
        # V1.1 for Application is a catchall flag for behavior which has been
        # determined to be desired for all peers running v1.0.x, but the
        # modification of which would cause incompatibilities.  Users should
        # leave this flag set to true.
        V1_1: true
        # V1_1_PVTDATA_EXPERIMENTAL is an Application capability to enable the
        # private data capability.  It is only supported when using peers built
        # with experimental build tag.  When set to true, private data
        # collections can be configured upon chaincode instantiation and
        # utilized within chaincode Invokes.
        # NOTE: Use of this feature with non "experimental" binaries on the
        # network may cause a fork.
        V1_1_PVTDATA_EXPERIMENTAL: false
        # V1_1_RESOURCETREE_EXPERIMENTAL is an Application capability to enable
        # the resources capability. Currently this is needed for defining
        # resource-based access control (RBAC). RBAC helps set fine-grained
        # access control on system resources such as the endorser and various
        # system chaincodes. Default is v1.0-based access control based on
        # CHANNEL_READERS and CHANNEL_WRITERS.
        # NOTE: Use of this feature with non "experimental" binaries on
        # the network may cause a fork.
        V1_1_RESOURCETREE_EXPERIMENTAL: false
   "
   } > /etc/hyperledger/fabric/configtx.yaml
   # Copy it to the data directory to make debugging easier
   cp /etc/hyperledger/fabric/configtx.yaml /$DATA
}

function generateChannelArtifacts() {
  
  which configtxgen
  if [ "$?" -ne 0 ]; then
    fatal "configtxgen tool not found. exiting"
  fi

  log "Generating orderer genesis block at $GENESIS_BLOCK_FILE"
  # Note: For some unknown reason (at least for now) the block file can't be
  # named orderer.genesis.block or the orderer will fail to launch!
 #cp /data/core.yaml $FABRIC_CFG_PATH/
  configtxgen -profile SampleSingleMSPBFTsmart -outputBlock $GENESIS_BLOCK_FILE
  if [ "$?" -ne 0 ]; then
    fatal "Failed to generate orderer genesis block"
  fi

  log "Generating channel configuration transaction at $CHANNEL_TX_FILE"
  configtxgen -profile SampleSingleMSPChannel -outputCreateChannelTx $CHANNEL_TX_FILE -channelID $CHANNEL_NAME
  if [ "$?" -ne 0 ]; then
    fatal "Failed to generate channel configuration transaction"
  fi

  for ORG in $PEER_ORGS; do
     initOrgVars $ORG
     log "Generating anchor peer update transaction for $ORG at $ANCHOR_TX_FILE"
     configtxgen -profile SampleSingleMSPChannel -outputAnchorPeersUpdate $ANCHOR_TX_FILE \
                 -channelID $CHANNEL_NAME -asOrg $ORG
     if [ "$?" -ne 0 ]; then
        fatal "Failed to generate anchor peer update for $ORG"
     fi
  done

}
function generateBftConfig() {
KEYFILE=""
SIGN_FILE=""
for entry in `ls /data/orgs/org0/admin/msp/keystore/`; do
    KEYFILE=${entry}
done
for entry in `ls /data/orgs/org0/admin/msp/signcerts/`; do
    SIGN_FILE=${entry}
done
echo "#The ID of the membership service provider (MSP)
MSPID=org0MSP

#Certificate of the node, compliant to Fabric's MSP guidelines
CERTIFICATE=/opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/peer.pem

#Private key of the node, compliant to Fabric's MSP guidelines
PRIVKEY=/opt/gopath/src/github.com/hyperledger/hyperledger-bftsmart-release-1.1/config/key.pem

#Number of signer/sending threads in the pool
PARELLELISM=10

#Maximum number of blocks to submit to each signer/sending thread
BLOCKS_PER_THREAD=10000

#IDs of the frontends present in the system, separate by commas
RECEIVERS=1000
" > /data/node.config
#cat /data/orgs/org0/admin/msp/keystore/$KEYFILE > /data/key.pem
#cat /data/orgs/org0/admin/msp/signcerts/$SIGN_FILE > /data/peer.pem

}

set -e

SDIR=$(dirname "$0")
source $SDIR/env.sh

main
