RTE_TARGET := $(if $(strip $(RTE_TARGET)), $(strip $(RTE_TARGET)), build)
RTE_SDK ?= /home/yuli9/qdma_ip_driver/QDMA/DPDK/

#Default BRAM size is set to 128K
#if modified the BRAM_SIZE, the same need to be set to the driver Makefile
BRAM_SIZE ?= 131072

# binary name
APP = test
APP1 = test_RR
# all source are stored in SRCS-y
SRCS-y := test.c pcierw.c
SRCS-x := test_RR.c pcierw.c

ifeq ($(CONFIG_RTE_LIBRTE_QDMA_GCOV),y)
  CFLAGS += -g -ftest-coverage -fprofile-arcs
  LDFLAGS += -lgcov
endif

# Build using pkg-config variables if possible
ifneq ($(shell pkg-config --exists libdpdk && echo 0),0)
$(error "no installation of DPDK found")
endif

all: shared shared1 static
RR: shared1
.PHONY: shared static shared1
shared: $(RTE_TARGET)/$(APP)-shared
	ln -sf $(APP)-shared $(RTE_TARGET)/$(APP)
shared1: $(RTE_TARGET)/$(APP1)-shared
	ln -sf $(APP1)-shared $(RTE_TARGET)/$(APP1)
static: $(RTE_TARGET)/$(APP)-static
	ln -sf $(APP)-static $(RTE_TARGET)/$(APP)

PKGCONF ?= pkg-config

# Common compiler flags
CFLAGS += -O3 $(shell $(PKGCONF) --cflags libdpdk)
CFLAGS += -DBRAM_SIZE=$(BRAM_SIZE)
CFLAGS += -DDPDK=1
CFLAGS += -DALLOW_EXPERIMENTAL_API
CFLAGS += -DRTE_LIBRTE_ETHDEV_DEBUG

# Gather DPDK libraries from pkg-config.
DPDK_LIBS        := $(shell $(PKGCONF) --libs libdpdk)
DPDK_LIBS_STATIC := $(shell $(PKGCONF) --static --libs libdpdk)
# Append the QDMA PMD library explicitly.
DPDK_LIBS        := $(DPDK_LIBS) -lrte_net_qdma
DPDK_LIBS_STATIC := $(DPDK_LIBS_STATIC) -lrte_net_qdma

LDFLAGS += $(DPDK_LIBS)

$(RTE_TARGET)/$(APP)-shared: $(SRCS-y) Makefile | $(RTE_TARGET)
	$(CC) $(CFLAGS) $(SRCS-y) -o $@ $(DPDK_LIBS)
$(RTE_TARGET)/$(APP1)-shared: $(SRCS-x) Makefile | $(RTE_TARGET)
	$(CC) $(CFLAGS) $(SRCS-x) -o $@ $(DPDK_LIBS)
$(RTE_TARGET)/$(APP)-static: $(SRCS-y) Makefile | $(RTE_TARGET)
	$(CC) $(CFLAGS) $(SRCS-y) -o $@ $(DPDK_LIBS_STATIC)

$(RTE_TARGET):
	@mkdir -p $@

.PHONY: clean
clean:
	rm -f $(RTE_TARGET)/$(APP) $(RTE_TARGET)/$(APP)-static $(RTE_TARGET)/$(APP)-shared
	test -d $(RTE_TARGET) && rm -r $(RTE_TARGET) || true
