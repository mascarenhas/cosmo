# $Id: Makefile,v 1.1.1.1 2007/11/26 17:12:24 mascarenhas Exp $

config_file:=config

ifneq '$(wildcard $(config_file))' ''
include $(config_file)
endif

$(config_file):
	chmod +x configure

all: src/cosmo/lpeg.so

src/cosmo/lpeg.so: src/cosmo/lpeg.o
	export MACOSX_DEPLOYMENT_TARGET="10.3"; $(CC) $(CFLAGS) $(LIB_OPTION) -o src/cosmo/lpeg.so src/cosmo/lpeg.o

install: $(config_file)
	mkdir -p $(LUA_DIR)
	mkdir -p $(LUA_DIR)/cosmo
	cp src/cosmo.lua $(LUA_DIR)/
	cp src/cosmo/grammar.lua $(LUA_DIR)/cosmo
	cp src/cosmo/fill.lua $(LUA_DIR)/cosmo
	cp src/cosmo/re.lua $(LUA_DIR)/cosmo
	mkdir -p $(LUA_LIBDIR)/cosmo
	cp src/cosmo/lpeg.so $(LUA_LIBDIR)/cosmo

install-rocks: install
	mkdir -p $(PREFIX)/samples
	cp -r samples/* $(PREFIX)/samples
	mkdir -p $(PREFIX)/doc
	cp -r doc/* $(PREFIX)/doc
	mkdir -p $(PREFIX)/tests
	cp -r tests/* $(PREFIX)/tests
	echo "Go to $(PREFIX) for samples and docs!"

test:
	cd tests && lua -l luarocks.require test_cosmo.lua

upload-cvs:
	darcs dist -d alien-current
	ncftpput -u mascarenhas ftp.luaforge.net cosmo/htdocs cosmo-current.tar.gz

dist:
	darcs dist -d cosmo-$(VERSION)

upload-dist:
	darcs push 139.82.100.4:public_html/cosmo/current
	ssh 139.82.100.4 "cd public_html/cosmo/current && make dist VERSION=$(VERSION)"
	darcs dist -d cosmo-$(VERSION)
	ncftpput -u mascarenhas ftp.luaforge.net cosmo/htdocs cosmo-$(VERSION).tar.gz
	ncftpput -u mascarenhas ftp.luaforge.net cosmo/htdocs doc/index.html

clean:
	rm src/cosmo/lpeg.o src/cosmo/lpeg.so
