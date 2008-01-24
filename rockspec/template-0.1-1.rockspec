package = "Template"

version = "0.1-1"

description = {
  summary = "Lpeg-based text templates",
  detailed = [[
     Template.* are Lpeg-based text template systems for Lua. They can be
     used to generate any kind of text such as HTML, XML, or even Lua
     code. Currently there are two systems, template.cosmo which is
     a reimplementation of Cosmo templates using Lpeg, and template.lp
     which is a reimplementation of CGILua's Lua Pages.
  ]],
  license = "MIT/X11",
  homepage = "http://www.lua.inf.puc-rio.br/~mascarenhas/template"
}

dependencies = { }

source = {
  url = "http://www.lua.inf.puc-rio.br/~mascarenhas/template/template-0.1.tar.gz"
}

build = {
   platforms = {
     unix = {
        type = "make",
	build_pass = true,
	build_target = "all",
   	install_target = "install-rocks",
       	build_variables = {
          LIB_OPTION = "$(LIBFLAG)",
          CFLAGS = "$(CFLAGS) -I$(LUA_INCDIR)",
       	},
       	install_variables = {
	  PREFIX  = "$(PREFIX)",
          LUA_BIN = "/usr/bin/env lua",
          LUA_DIR= "$(LUADIR)",
          LUA_LIBDIR = "$(LIBDIR)"
       	}
     },
     win32 = {
        type = "make",
	build_pass = true,
	build_target = "all",
   	install_target = "install-rocks",
       	build_variables = {
          LIB_OPTION = "$(LUA_LIBDIR)\\lua5.1.lib",
          CFLAGS = "$(CFLAGS)",
	  LUA_INCLUDE = "$(LUA_INCDIR)"
       	},
       	install_variables = {
	  PREFIX  = "$(PREFIX)",
          LUA_BIN = "/usr/bin/env lua",
          LUA_DIR= "$(LUADIR)",
          LUA_LIBDIR = "$(LIBDIR)"
       	}
     }
  }
}
