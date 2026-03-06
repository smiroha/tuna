# tuna@
_Erlang application for testing RabbitMQ Cluster (and quorum queues)._

---
## Scheme


## Usage
### Prerequisites
- Docker
- Erlang 25

### - Installation
```sh
# Example installation steps
git clone git@github.com:smiroha/tuna.git master
cd tuna
gmake
```

```sh
# Example local launch application steps
gmake ; _rel/tuna_release/bin/tuna_release console
```

```sh
# Example local launch Rabbit cluster steps
docker compose -f ./build/docker-compose.yaml down -v ; docker compose -f ./build/docker-compose.yaml up
```

```sh
# Chaos test (Pumba + network issues)
# For Docker Desktop (macOS), set Docker socket path and free host ports:
DOCKER_HOST_SOCKET=$HOME/.docker/run/docker.sock \
RMQ_AMQP_PORT=5673 RMQ_MGMT_PORT=15673 \
docker compose -f ./build/docker-compose.yaml up -d --build
```

### Monitoring (Prometheus + Grafana)
- Prometheus: `http://localhost:9090`
- Pushgateway: `http://localhost:9091`
- Grafana: `http://localhost:3000` (`admin` / `admin`)
- Preloaded dashboard: `RabbitMQ: Classic vs Quorum`
- Preloaded dashboard: `RabbitMQ Reliability (Classic vs Quorum)`

### Reliability scenario
1. Start infra (`RabbitMQ + chaos + monitoring`):
```sh
DOCKER_HOST_SOCKET=$HOME/.docker/run/docker.sock \
RMQ_AMQP_PORT=5673 RMQ_MGMT_PORT=15673 \
docker compose -f ./build/docker-compose.yaml up -d --build
```
2. Start Erlang load app (multi publisher + classic/quorum consumers + metrics push):
```sh
# if RMQ_AMQP_PORT is not 5672, update {amqp_port, ...} in config/sys.config
gmake ; _rel/tuna_release/bin/tuna_release console
```
3. Watch Grafana dashboard `RabbitMQ Reliability (Classic vs Quorum)` and compare:
- `publish confirm ack/nack/return`
- `consumer gaps/duplicates/redelivered`
- `publisher inflight`

## TODO
- Redesign publisher: split publisher and message generator processes 
