1) Build image
- fabric-ca
- fabric-ca-peer
- fabric-ca-orderer-bftsmart
- fabric-ca-tools
2) Clean data
- ./stop.sh
- ./clean.sh
3) Create network bridge
- docker network create fabric-ca-orderer-bftsmart
4) Start network
- docker-compose up -d

