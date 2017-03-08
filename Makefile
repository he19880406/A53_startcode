# Copyright (C) ARM Limited, 2014. All rights reserved.
#
# This example is intended to be built with ARM Compiler 6
#
# Environmental variables for build options that the user might wish to change
#
# Variable       Default Value           Example Value
# -----------    -------------           -------------
# QUIET          @ (terse output)        leave blank for detailed output
# OPT_LEVEL      1                       2
# DEFINES                                -D MYDEFINE
# SUPPRESS                               --diag_suppress=1234
# APP            startup_v8_FVP.axf      myapp.axf
# PLATFORM       AEM                     CORTEXA will add extra code 
#                                        for initialising Cortex-A53/A57

QUIET ?= @
OPT_LEVEL ?= 1
APP ?= startup_v8.elf
PLATFORM ?= AEM
OUTPUTCHAN ?= UART

ARCH 			:= aarch64
DEBUG_FLAGS = -g

ifeq ($(QUIET),@)
PROGRESS = @echo Compiling $<...
endif

CROSS_COMPILE=/mnt/fileroot/yan.wang/armv8/toolchain/aarch64-maremetal/bin/aarch64-none-elf-
CC = ${CROSS_COMPILE}gcc
AS = ${CROSS_COMPILE}gcc
LINK = ${CROSS_COMPILE}ld
SRC_DIR = src
ARMCLANG_DIR = armclang
OBJ_DIR = obj

INCLUDES = -I$(SRC_DIR)

ASFLAGS			+= 	-nostdinc -ffreestanding -Wa,--fatal-warnings	\
				-mgeneral-regs-only -D__ASSEMBLY__		\
				 ${INCLUDES}
CFLAGS			+= 	-nostdinc -pedantic -ffreestanding -Wall	\
				-Werror -mgeneral-regs-only -std=c99 -c -Os	\
				 ${INCLUDES}
CFLAGS			+=	-ffunction-sections -fdata-sections

LDFLAGS			+=	--fatal-warnings -O1
LDFLAGS			+=	--gc-sections
LDFLAGS			+=  -T a53boot.ld

APP_C_SRC := $(wildcard $(SRC_DIR)/*.c)
APP_ARMCLANG_SRC := $(wildcard $(ARMCLANG_DIR)/*.s)
OBJ_FILES := $(APP_C_SRC:$(SRC_DIR)/%.c=$(OBJ_DIR)/%.o) \
             $(APP_ARMCLANG_SRC:$(ARMCLANG_DIR)/%.s=$(OBJ_DIR)/%.o)
VPATH = $(SRC_DIR):$(ARMCLANG_DIR)
DEP_FILES := $(OBJ_FILES:%=%.d)

.phony: all clean

all: $(APP)

rebuild:	clean all

$(APP): $(OBJ_DIR) $(OBJ_FILES) a53boot.ld
	@echo Linking $@
	$(LINK) $(LDFLAGS) --output $@ $(OBJ_FILES)
	@echo Done.

clean:
	@echo "  CLEAN"
	${Q}rm -rf ${OBJ_DIR}

depend:		clean ${OBJ_FILES}

$(OBJ_DIR):
	mkdir -p $@

$(OBJ_DIR)/%.o : %.c	
	$(CC) $(CFLAGS) -c -o $@ $<

$(OBJ_DIR)/%.o : %.s	
	$(CC) $(AFLAGS_ARMCLANG) -c -o $@ $<

-include $(DEP_FILES)

help:
	@echo make [OPTIONS]
	@echo 'PLATFORM=   [AEM/CORTEXA]       Choose VE FVP target: AEMv8 or Cortex-A53/A57'
	@echo ''
	@echo 'NOTE: The first value in the options indicates the default setting.'
