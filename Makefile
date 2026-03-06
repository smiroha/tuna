PROJECT = tuna
PROJECT_DESCRIPTION = Application for testing RabbitMQ cluster
PROJECT_VERSION = 0.1.0

dep_amqp_client   = hex 3.11.11
dep_rabbit_common = hex 3.11.11

DEPS := $(shell sed -n 's/^dep_\([^ ^=]*\).*/\1/p' $(lastword $(MAKEFILE_LIST)))

RELEASE_TAR = false
REL_DEPS += relx

include erlang.mk
