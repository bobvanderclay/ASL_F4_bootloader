# This file is part of the Racecapture/Track project
#
# Copyright (C) 2013 Autosport Labs
#
# Author(s):
# 	Andrey Smirnov <andrew.smirnov@gmail.com>
# 	Jeff Ciesielski <jeffciesielski@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This file can be used to autoconfigure your board for ease of
# building, otherwise it passes the BOARD environment variable to the
# rest of the makefile
-include config.mk

#ifeq ($(APP),)
#$(error APP is not defined.  Pass it in as APP= or create a config.mk file)
#endif

ifeq ($(APP_PATH),)
APP_PATH = .
endif

ifeq ($(CPU_TYPE),)
$(error CPU_TYPE is not defined, please ensure it is defined in your cpu config.mk)
endif

PREFIX	?= arm-none-eabi

CC      := $(PREFIX)-gcc
AS      := $(PREFIX)-as
CXX     := $(PREFIX)-g++
AR      := $(PREFIX)-ar
NM      := $(PREFIX)-nm
OBJCOPY := $(PREFIX)-objcopy
OBJDUMP := $(PREFIX)-objdump
SIZE    := $(PREFIX)-size

OPENOCD := openocd
DDD     := ddd
GDB     := $(PREFIX)-gdb

#application libraries
include libs.mk

CFLAGS ?= -Os -g -Wall -fno-common -c -mthumb \
	  -mcpu=$(CPU_TYPE) -MD -std=gnu99

INCLUDES += $(CPU_INCLUDES) $(BOARD_INCLUDES) $(LIB_INCLUDES) $(APP_INCLUDES)
CFLAGS += $(INCLUDES) $(CPU_DEFINES) $(BOARD_DEFINES) $(APP_DEFINES) $(CPU_FLAGS)
ASFLAGS += -mcpu=$(CPU_TYPE) $(FPU) -g -Wa,--warn

LIBS = -lnosys
LIBS += $(addprefix -l,$(BASE_LIBS))

LDFLAGS ?= --specs=nano.specs -lc -lgcc $(LIBS) -mcpu=$(CPU_TYPE) -g -gdwarf-2 \
	-L. -Lcpu/common -L$(CPU_BASE) -T$(CPU_LINK_MEM) -Tlink_sections.ld \
	-nostartfiles -Wl,--gc-sections -mthumb -mcpu=$(CPU_TYPE) \
	-msoft-float -Wl,--Map=$(TARGET).map

# Be silent per default, but 'make V=1' will show all compiler calls.
ifneq ($(V),1)

Q := @
# Do not print "Entering directory ...".
MAKEFLAGS += --no-print-directory
endif

# common objects
OBJS += $(CPU_OBJS) $(BOARD_OBJS) $(APP_OBJS)

ifeq ($(TARGET),)
$(error TARGET is not defined, please define it in your applications config.mk)
endif

LIBS_ALL = $(addprefix lib,$(BASE_LIBS:=.a))

all: messages $(LIBS_ALL) $(TARGET).bin

libstm32f4_periph.a: $(STM32F4_PERIPH_OBJS)
	$(Q)$(AR) $(ARFLAGS) $@ $^

libstm32_usb.a: $(STM32_USB_OBJS)
	$(Q)$(AR) $(ARFLAGS) $@ $^

$(TARGET).bin: $(TARGET).elf
	@printf "  OBJCOPY $(subst $(shell pwd)/,,$(@))\n"
	$(Q)$(PREFIX)-objcopy -Obinary $< $@
	$(SIZE) $<

$(TARGET).elf: $(OBJS)
	@printf "  LD      $(subst $(shell pwd)/,,$(@))\n"
	$(Q)$(CC) -o $@ $(OBJS) $(LDFLAGS)

.c.o:
	@printf "  CC      $(subst $(shell pwd)/,,$(@))\n"
	$(Q)$(CC) $(CFLAGS) -c -o $@ $<

.s.o:
	@printf "  AS      $(subst $(shell pwd)/,,$(@))\n"
	$(Q)$(CC) $(ASFLAGS) -c -o $@ $<

messages:
	@printf " Generating messages\n"
	$(Q)xbvcgen -i upgrade_agent/messages.yaml -o msgs -l c -l python -t device -c
	$(Q)cp -f msgs/C/* upgrade_agent
	$(Q)cp -f msgs/Python/* host_tools
	$(Q)rm -rf msgs

clean:
	$(Q)rm -f *.o *.a *.d ../*.o ../*.d $(OBJS) $(LIBS_ALL)\
	$(STM32F4_PERIPH_OBJS) \
	$(shell find . -name "*.d") \
	$(TARGET).bin $(TARGET).elf \
	upgrade_agent/xbvc_core.c \
	upgrade_agent/xbvc_core.h \
	upgrade_agent/cobs.c \
	upgrade_agent/cobs.h \
	host_tools/cobs.py* \
	host_tools/xbvc_py*

flash: $(TARGET).bin
	$(APP_FLASH)

debug: $(TARGET).bin
	$(OPENOCD) -f $(APP_PATH)/openocd.cfg

ddd: $(TARGET).elf
	$(DDD) --eval-command="target remote localhost:3333" --debugger $(GDB) $(TARGET).elf

gdb: $(TARGET).elf
	$(GDB) -ex "target ext localhost:3333" -ex "mon reset halt" -ex "mon arm semihosting enable" $(TARGET).elf

.PHONY: clean flash debug ddd messages
