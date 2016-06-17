local coroutine = require "coroutine"
local ok, taggedcoro = pcall(require, "taggedcoro")
if ok then
  coroutine = taggedcoro.fortag("cosmo")
end

local grammar = require "cosmo.grammar"
local interpreter = require "cosmo.fill"
local loadstring = loadstring or load

local cosmo = {}

function cosmo.yield(...)
  return coroutine.yield(...)
end

local preamble = [[
    local is_callable, insert, concat, setmetatable, getmetatable, type, wrap, tostring, check_selector = ...
    local function unparse_name(parsed_selector)
      local name = parsed_selector:match("^env%%['([%%w_]+)'%%]$")
      if name then name = "$" .. name end
      return name or parsed_selector
    end
    local function prepare_env(env, parent)
      local __index = function (t, k)
                        local v = env[k]
                        if not v then
                          v = parent[k]
                        end
                        return v
                      end
      local __newindex = function (t, k, v)
                           env[k] = v
                         end
      return setmetatable({ self = env }, { __index = __index, __newindex = __newindex })
    end
    local id = function () end
    local template_func = %s
    return function (env, opts)
             opts = opts or {}
             local out = opts.out or {}
             template_func(out, env, opts)
             return concat(out, opts.delim)
           end
]]

local compiled_template = [[
    function (out, env, opts)
      if type(env) == "string" then env = { it = env } end
      $parts[=[
          insert(out, $quoted_text)
      ]=],
      [=[
          local selector_name = unparse_name($selector)
          local selector = $parsed_selector
          $if_subtemplate[==[
              local subtemplates = {}
              $subtemplates[===[
                  subtemplates[$i] = $subtemplate
              ]===]
              local default = id
              if opts.fallback then
                default = subtemplates[1]
              end
              $if_args[===[
                  check_selector(selector_name, selector)
                  for e, literal in wrap(selector), $args, true do
                    if literal then
                      insert(out, tostring(e))
                    else
                      if type(e) ~= "table" then
                        e = prepare_env({ it = tostring(e) }, env)
                      else
                        e = prepare_env(e, env)
                      end
                      (subtemplates[e.self._template or 1] or default)(out, e, opts)
                    end
                  end
              ]===],
              [===[
                  if type(selector) == 'table' then
                    for _, e in ipairs(selector) do
                      if type(e) ~= "table" then
                        e = prepare_env({ it = tostring(e) }, env)
                      else
                        e = prepare_env(e, env)
                      end
                      (subtemplates[e.self._template or 1] or default)(out, e, opts)
                    end
                  else
                    check_selector(selector_name, selector)
                    for e, literal in wrap(selector), nil, true do
                      if literal then
                        insert(out, tostring(e))
                      else
                        if type(e) ~= "table" then
                          e = prepare_env({ it = tostring(e) }, env)
                        else
                          e = prepare_env(e, env)
                        end
                        (subtemplates[e.self._template or 1] or default)(out, e, opts)
                      end
                    end
                  end
              ]===]
          ]==],
          [==[
              $if_args[===[
                  check_selector(selector_name, selector)
                  selector = selector($args, false)
                  insert(out, tostring(selector))
              ]===],
              [===[
                  if is_callable(selector) then
                    insert(out, tostring(selector()))
                  else
                    if not selector and opts.passthrough then
                      selector = selector_name
                    end
                    insert(out, tostring(selector or ""))
                  end
              ]===]
          ]==]
      ]=]
    end
]]

local function is_callable(f)
  if type(f) == "function" then return true end
  local meta = getmetatable(f)
  if meta and meta.__call then return true end
  return false
end

local function check_selector(name, selector)
  if not is_callable(selector) then
    error("selector " .. name .. " is not callable but is " .. type(selector))
  end
end

local function compile_template(chunkname, template_code)
   local template_func, err = loadstring(string.format(preamble, template_code), chunkname)
   if not template_func then
     error("syntax error when compiling template: " .. err)
   else
     return template_func(is_callable, table.insert, table.concat, setmetatable, getmetatable, type,
                          coroutine.wrap, tostring, check_selector)
   end
end

local compiler = {}

function compiler.template(template)
  assert(template.tag == "template")
  local parts = {}
  for _, part in ipairs(template.parts) do
    parts[#parts+1] = compiler[part.tag](part)
  end
  return interpreter.fill(compiled_template, { parts = parts })
end

function compiler.text(text)
  assert(text.tag == "text")
  return { _template = 1, quoted_text = string.format("%q", text.text) }
end

function compiler.appl(appl)
  assert(appl.tag == "appl")
  local selector, args, subtemplates = appl.selector, appl.args, appl.subtemplates
  local ta = { _template = 2, selector = string.format("%q", selector),
      parsed_selector = selector }
   local do_subtemplates = function ()
                             for i, subtemplate in ipairs(subtemplates) do
                               cosmo.yield{ i = i, subtemplate = compiler.template(subtemplate) }
                             end
                           end
   if #subtemplates == 0 then
     if args and args ~= "" and args ~= "{}" then
       ta.if_subtemplate = { { _template = 2, if_args = { { _template = 1, args = args } } } }
     else
       ta.if_subtemplate = { { _template = 2, if_args = { { _template = 2 } } } }
     end
   else
     if args and args ~= "" and args ~= "{}" then
       ta.if_subtemplate = { { _template = 1, subtemplates = do_subtemplates,
                               if_args = { { _template = 1, args = args } } } }
     else
       ta.if_subtemplate = { { _template = 1, subtemplates = do_subtemplates,
                               if_args = { { _template = 2 } } } }
     end
   end
   return ta
end

local cache = {}
setmetatable(cache, { __index = function (tab, key)
                                   local new = {}
                                   tab[key] = new
                                   return new
                                end,
                      __mode = "v" })

function cosmo.compile(template, chunkname, opts)
  opts = opts or {}
  template = template or ""
  chunkname = chunkname or template
  local compiled_template = cache[template][chunkname]
  grammar.ast = opts.parser or grammar.default
  if not compiled_template then
    compiled_template = compile_template(chunkname, compiler.template(grammar.ast:match(template)))
    cache[template][chunkname] = compiled_template
  end
  return compiled_template
end

local filled_templates = {}
setmetatable(filled_templates, { __mode = "k" })

function cosmo.fill(template, env, opts)
   opts = opts or {}
   template = template or ""
   local start = template:match("^(%[=*%[)")
   if start then template = template:sub(#start + 1, #template - #start) end
   if filled_templates[template] then
      return cosmo.compile(template, opts.chunkname, opts.parser)(env, opts)
   else
      filled_templates[template] = true
      return interpreter.fill(template, env, opts)
   end
end

local nop = function () end

function cosmo.cond(bool, table)
   if bool then
      return function () cosmo.yield(table) end
   else
      return nop
   end
end

cosmo.f = cosmo.compile

function cosmo.c(bool)
   if bool then
      return function (table)
                return function () cosmo.yield(table) end
             end
   else
      return function (table) return nop end
   end
end

function cosmo.map(arg, has_block)
   if has_block then
      for _, item in ipairs(arg) do
         cosmo.yield(item)
      end
   else
      return table.concat(arg)
   end
end

function cosmo.inject(arg)
   cosmo.yield(arg)
end

function cosmo.cif(arg, has_block)
  if not has_block then error("this selector needs a block") end
  if arg[1] then
    arg._template = 1
  else
    arg._template = 2
  end
  cosmo.yield(arg)
end

function cosmo.concat(arg)
  local list, sep = arg[1], arg[2] or ", "
  local size = #list
  for i, e in ipairs(list) do
    if type(e) == "table" then
      if i ~= size then
        cosmo.yield(e)
        cosmo.yield(sep, true)
      else
        cosmo.yield(e)
      end
    else
      if i ~= size then
        cosmo.yield{ it = e }
        cosmo.yield(sep, true)
      else
        cosmo.yield{ it = e }
      end
    end
  end
end

function cosmo.make_concat(list)
  return function (arg)
           local sep = (arg and arg[1]) or ", "
           local size = #list
           for i, e in ipairs(list) do
             if type(e) == "table" then
               if i ~= size then
                 cosmo.yield(e)
                 cosmo.yield(sep, true)
               else
                 cosmo.yield(e)
               end
             else
               if i ~= size then
                 cosmo.yield{ it = e }
                 cosmo.yield(sep, true)
               else
                 cosmo.yield{ it = e }
               end
             end
           end
         end
end

function cosmo.cfor(args)
  local name, list, args = args[1], args[2], args[3]
  if type(list) == "table" then
    for i, item in ipairs(list) do
      cosmo.yield({ [name] = item, i = i })
    end
  else
    for item, literal in coroutine.wrap(list), args, true do
      if literal then
        cosmo.yield(item, true)
      else
        cosmo.yield({ [name] = item })
      end
    end
  end
end

return cosmo
