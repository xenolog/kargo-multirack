default: help
all: help

#TMP:=$(shell pwd)/tmp-$(shell date "+%Y%m%d-%H%M%S")
TMP:=$(shell pwd)/tmp-$(shell date "+%Y%m%d")
CURL=curl -sSf

CONTAINER="xenolog/k8s-rr-container"

BUILDER_ALPINE=3.4
BUILDER_FLAG=$(TMP)/.container_ready

CONFD_VERSION=0.12.1
CONFD_SRC_URL=https://codeload.github.com/bacongobbler/confd/zip/v$(CONFD_VERSION)
CONFD_SRC_DIR=$(TMP)/confd-$(CONFD_VERSION)
CONFD_BIN=$(CONFD_SRC_DIR)/bin/confd

BIRD_VERSION=1.6.2
BIRD_SRC_TARBALL=bird-$(BIRD_VERSION).tar.gz
BIRD_SRC_URL=ftp://bird.network.cz/pub/bird/$(BIRD_SRC_TARBALL)
BIRD_SRC_DIR=$(TMP)/bird-$(BIRD_VERSION)
BIRD_BIN=$(BIRD_SRC_DIR)/bird
BIRDC_BIN=$(BIRD_SRC_DIR)/birdc
BIRDCL_BIN=$(BIRD_SRC_DIR)/birdcl

tmp:
	mkdir -p $(TMP)

.PHONY: clean
clean:
	rm -rf tmp-*

$(BUILDER_FLAG): tmp
	(docker build -t kargo-multirack-builder -f Dockerfile-builder .)
	(echo > $(BUILDER_FLAG))

.PHONY: builder
builder: $(BUILDER_FLAG)


$(CONFD_SRC_DIR): tmp
	(test -d $(CONFD_SRC_DIR) && rm -rf $(CONFD_SRC_DIR) ; true)
	(cd $(TMP) && curl -o confd-$(CONFD_VERSION).zip $(CONFD_SRC_URL))
	(cd $(TMP) && unzip -q -o confd-$(CONFD_VERSION).zip)

$(CONFD_BIN): $(BUILDER_FLAG) $(CONFD_SRC_DIR)
	(cd $(CONFD_SRC_DIR) && docker run -ti --rm -v `pwd`:/go/src/github.com/kelseyhightower/confd kargo-multirack-builder build_confd.sh)

.PHONY: build-confd
build-confd: $(CONFD_BIN)



$(BIRD_SRC_DIR): tmp
	(test -d $(BIRD_SRC_DIR) && rm -rf $(BIRD_SRC_DIR) ; true)
	(cd $(TMP) && curl $(BIRD_SRC_URL) | tar xzf -)

$(BIRD_BIN): $(BUILDER_FLAG) $(BIRD_SRC_DIR)
	(cd $(BIRD_SRC_DIR) && docker run -ti --rm -v `pwd`:/bird_src kargo-multirack-builder build_bird.sh)

.PHONY: build-bird
build-bird: $(BIRD_BIN)


.PHONY: build-container
build-container: $(CONFD_BIN) $(BIRD_BIN)
	(mkdir -p root/bin)
	(cp $(CONFD_BIN) root/bin/)
	(cp $(BIRD_BIN) root/bin/)
	(cp $(BIRDC_BIN) root/bin/)
	(cp $(BIRDCL_BIN) root/bin/)
	(docker build -t $(CONTAINER) -f Dockerfile . | tee $(TMP)/build.log)

.PHONY: list-tags
list-tags:
	docker images | grep xenolog/k8s-rr-container
.PHONY: help
## Display this help text
help:
	@echo
	@echo "Use make with following parameter:"
	@echo "  build-container   --  build container"
	@echo "  list-tags         --  list tags of existing containers"
	@echo "  clean             --  remove ALL temporary files and directories"
	@echo
