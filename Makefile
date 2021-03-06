
SHELL=/bin/bash
.SHELLFLAGS=-O extglob -o errexit -o pipefail -o nounset -c

.PHONY: config echo-config

IMAGE_NAME?=kubernetes-anywhere
IMAGE_VERSION?=v0.0.1

# sorry windows and non amd64
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
	OS = linux
endif
ifeq ($(UNAME_S),Darwin)
	OS = darwin
endif

CONF_TOOL_VERSION = 4.6
KCONFIG_FILES = $(shell find . -name 'Kconfig')

CLOUD_PROVIDER = $(shell jq -r '.phase1.cloud_provider' .config.json 2>/dev/null)
CLUSTER_NAME = $(shell jq -r '.phase1.cluster_name' .config.json 2>/dev/null)
TMP_DIR = $(CLUSTER_NAME)/.tmp

default:
	$(MAKE) deploy

config:
	CONFIG_="." kconfig-conf Kconfig

menuconfig:
	CONFIG_="." kconfig-mconf Kconfig

.config: $(KCONFIG_FILES)
	$(MAKE) config

.config.json: .config
	util/config_to_json $< > $@

echo-config: .config.json
	cat $<

deploy-cluster destroy-cluster: .config.json
	$(MAKE) do WHAT=$@

# For maximum usefulness, use this target with "make -s" to silence any trace output, e.g.:
#   $ export KUBECONFIG=$(make -s kubeconfig-path)
kubeconfig-path: .config.json
	@$(eval KUBECONFIG_PATH := $(shell pwd)/phase1/$(CLOUD_PROVIDER)/$(CLUSTER_NAME)/kubeconfig.json)
	@if [ ! -e "$(KUBECONFIG_PATH)" ]; then \
		echo "Cannot find kubeconfig file. Have you started a cluster with \"make deploy\" yet?" > /dev/stderr; \
		exit 1; \
	fi
	@echo $(KUBECONFIG_PATH)

validate: .config.json
	KUBECONFIG="$$(pwd)/phase1/$(CLOUD_PROVIDER)/$(CLUSTER_NAME)/kubeconfig.json" ./util/validate

addons: .config.json
	KUBECONFIG="$$(pwd)/phase1/$(CLOUD_PROVIDER)/$(CLUSTER_NAME)/kubeconfig.json" ./phase3/do deploy

deploy: | deploy-cluster validate addons
destroy: | destroy-cluster

do:
	( cd "phase1/$(CLOUD_PROVIDER)"; ./do $(WHAT) )

docker-build:
	docker build -t $(IMAGE_NAME):$(IMAGE_VERSION) .

docker-dev: docker-build
	${info Starting Kuberetes Anywhere deployment shell in a container}
	docker run -it --rm --env="PS1=[container]:\w> " --net=host --volume="`pwd`:/opt/kubernetes-anywhere" $(IMAGE_NAME):$(IMAGE_VERSION) /bin/bash

docker-push: docker-build
	docker push $(IMAGE_NAME):$(IMAGE_VERSION)

clean:
	( if [[ -e .config.json ]];then rm -rf phase3/${CLOUD_PROVIDER}/.tmp/ phase1/${CLOUD_PROVIDER}/${CLUSTER_NAME}/; fi )

fmt:
	for f in $$(find . -name '*.jsonnet'); do jsonnet fmt -i -n 2 $${f}; done;
	# for f in $$(find . -name '*.json'); do jq -S '.' "$${f}" | ex -sc "wq!$${f}" /dev/stdin; done;
