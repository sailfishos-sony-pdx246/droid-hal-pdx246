# SPDX-FileCopyrightText: Johannes Meyer zum Alten Borgloh
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds simg2img for the droid-hal-pdx246-tools package.
#
# Rewritten after dhd's own helpers/simg2img.mk (mer-hybris/droid-hal-device,
# RPM licence BSD; that file carries no notice of its own): the same
# interface and make skeleton, with -std=gnu++17.
#
# dhd (rpm/dhd/droid-hal-device.inc) uses this file instead of its own
# helpers/simg2img.mk because it exists at rpm/helpers/simg2img.mk. dhd runs it as
#   make -f rpm/helpers/simg2img.mk -C $ANDROID_ROOT/system/core/libsparse
# and passes the source list in SIMG2IMG_SOURCES.
#
# Why: the same as img2simg.mk next to this file. Android 16's libsparse needs
# C++17 (std::optional from android::base::MappedFile::Create), and dhd's own
# makefile compiles with -std=gnu++14.

SIMG2IMG_SOURCES ?= $(error SIMG2IMG_SOURCES is not set; droid-hal-device.inc passes it)

CXXFLAGS += -std=gnu++17
CPPFLAGS += -Iinclude -I../../libbase/include
LDLIBS += -lz

# dhd lists some sources with a .c suffix that are .cpp files on Android 13 and
# later; make's built-in rules find the .cpp file for each object.
SIMG2IMG_OBJS := $(patsubst %.cpp,%.o,$(patsubst %.c,%.o,$(SIMG2IMG_SOURCES)))

all: simg2img

simg2img: $(SIMG2IMG_OBJS)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

clean:
	rm -f $(SIMG2IMG_OBJS) simg2img

.PHONY: all clean
