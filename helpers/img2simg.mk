# SPDX-FileCopyrightText: Johannes Meyer zum Alten Borgloh
# SPDX-License-Identifier: Apache-2.0
#
# Builds img2simg for the droid-hal-pdx246-tools package.
#
# Rewritten after dhd's own helpers/img2simg.mk (mer-hybris/droid-hal-device,
# RPM licence BSD; that file carries no notice of its own): the same
# interface and make skeleton, with -std=gnu++17.
#
# dhd (rpm/dhd/droid-hal-device.inc) uses this file instead of its own
# helpers/img2simg.mk because it exists at rpm/helpers/img2simg.mk. dhd runs it as
#   make -f rpm/helpers/img2simg.mk -C $ANDROID_ROOT/system/core/libsparse
# and passes the source list in IMG2SIMG_SOURCES.
#
# Why: dhd's makefile compiles with -std=gnu++14. On the Android 16 tree,
# libsparse/output_file.cpp calls android::base::MappedFile::Create(), which returns
# std::optional (system/libbase a5fcaab, system/core effce46f3, August 2025), so the
# droid-hal build stops in its build step with "'optional' in namespace 'std' does
# not name a template type". gnu++17 builds it (tested with g++ 15 on a copy of the
# sources; the SDK's cross g++ is 13.4).

IMG2SIMG_SOURCES ?= $(error IMG2SIMG_SOURCES is not set; droid-hal-device.inc passes it)

CXXFLAGS += -std=gnu++17
CPPFLAGS += -Iinclude -I../../libbase/include
LDLIBS += -lz

# dhd lists some sources with a .c suffix that are .cpp files on Android 13 and
# later; make's built-in rules find the .cpp file for each object.
IMG2SIMG_OBJS := $(patsubst %.cpp,%.o,$(patsubst %.c,%.o,$(IMG2SIMG_SOURCES)))

all: img2simg

img2simg: $(IMG2SIMG_OBJS)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

clean:
	rm -f $(IMG2SIMG_OBJS) img2simg

.PHONY: all clean
