#
# File:
#    Makefile
#
# Description:
#    Makefile for the CODA 3.0 primary and secondary readout lists 
#    running on an Intel-based controller running Linux
#
#
# Uncomment DEBUG line for debugging info ( -g and -Wall )
DEBUG=1
#

# Plug in your primary readout lists here..
VMEROL		= ti_slave_list.so ts_list.so ts_list_stream.so gt_list.so ti_master_list.so
# Add shared library dependencies here.  (jvme, ti, td, ts, sd, ctp are already included)
ROLLIBS		= 

LINUXVME_LIB	?= $(CODA)/linuxvme/lib
LINUXVME_INC	?= $(CODA)/linuxvme/include
LINUXVME_BIN	?= $(CODA)/linuxvme/bin

# DEFs for compiling primary readout lists
CC			= gcc
AR                      = ar
RANLIB                  = ranlib
ifdef DEBUG
CFLAGS			= -Wall -g
else
CFLAGS			= -O3
endif
CFLAGS			+= -w -I. -I${LINUXVME_INC} -I/usr/include -I${CODA}/common/include\
			  -L${LINUXVME_LIB} -L. -L${CODA}/${MACHINE}/lib -DJLAB
CFLAGS			+= -lrt -lpthread -ljvme -lti -ltd -lts -lsd -lctp -lssp -lfadc -lremex -let $(ROLLIBS)
CFLAGS			+= -DLINUX -DDAYTIME=\""`date`"\"

# DEFs for compiling CODA readout lists
CCRL			= ${CODA_BIN}/ccrl
CODA_INCS		= -I.  -I${LINUXVME_INC} -I${CODA}/common/include
CODA_LIBDIRS            = -L${LINUXVME_LIB} -L. -L${CODA}/${MACHINE}/lib
CODA_LIBS		= -ljvme
CODA_DEFS		= -DLINUX -DDAYTIME=\""`date`"\"
CODA_CFLAGS		= -O -w -fpic -shared ${CODA_INCS} ${CODA_LIBDIRS} \
			  ${CODA_LIBS} ${CODA_DEFS}
ifdef DEBUG
CODA_CFLAGS		+= -Wall -g
endif
CRLFILES		= $(wildcard *.crl)
CFILES			= $(CRLFILES:.crl=.c)
SOBJS			= $(CRLFILES:.crl=.so)

ifeq ($(ARCH),x86_64)
	libdir:=/usr/lib64/gef
else
	libdir:=/usr/lib/gef
endif

# End in error, if the gefvme-kmod-common RPM is not installed.
#ifeq (,$(wildcard $(libdir)/libvme.a))
#$(error gefvme-kmod-common RPM not installed!)
#endif

all: $(VMEROL) $(SOBJS) 

crl: $(SOBJS)

event_list.so: event_list.c
	@echo
	@echo "Building $@ from $<"
	@echo
	${CC} ${CODA_CFLAGS} -o $@ $<

test_list_v3.so: test_list_v3.c
	@echo
	@echo "Building $@ from $<"
	@echo
	${CC} ${CODA_CFLAGS} -o $@ $<


%.c: %.crl Makefile
	@echo
	@echo "Converting $< to $@"
	@${CCRL} $<

%.so: %.c Makefile
	@echo
	@echo "Building $@ from $<"
	@echo
	$(CC) -fpic -shared  $(CFLAGS) -DINIT_NAME=$(@:.so=__init) -DINIT_NAME_POLL=$(@:.so=__poll) -o $@ $<

clean distclean:
	@rm -f  $(VMEROL) $(SOBJS) $(CFILES) *~ 

.PHONY: all
