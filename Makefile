# $Id: Makefile,v 1.1.1.1 2007/11/26 17:12:24 mascarenhas Exp $

config_file:=config

ifneq '$(wildcard $(config_file))' ''
include $(config_file)
endif

$(config_file):
	chmod +x configure

install: $(config_file)
	mkdir -p $(LUA_DIR)
	mkdir -p $(LUA_DIR)/template
	cp src/template/cosmo.lua $(LUA_DIR)/template
	cp src/template/re.lua $(LUA_DIR)/template

install-rocks: install
	mkdir -p $(PREFIX)/samples
	cp samples/*.lua $(PREFIX)/samples
	mkdir -p $(PREFIX)/doc
	cp -r doc/* $(PREFIX)/doc
	mkdir -p $(PREFIX)/tests
	cp -r tests/* $(PREFIX)/tests
	echo "Go to $(PREFIX) for samples and docs!"

test:
	cd tests && lua test.lua

clean:
