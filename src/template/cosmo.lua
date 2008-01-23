local require = require

local grammar = require "template.cosmo_grammar"
local loadstring = loadstring

module(..., package.seeall)

local function parse_selector(selector)
  selector = string.sub(selector, 2, #selector)
  local parts = {}
  for w in string.gmatch(selector, "[^/]+") do
    local n = tonumber(w)
    if n then
      table.insert(parts, "[" .. n .. "]")
    else
      table.insert(parts, "['" .. w .. "']")
    end
  end
  return "env" .. table.concat(parts)
end

local function get_selector(env, selector)
  selector = string.sub(selector, 2, #selector)
  local parts = {}
  for w in string.gmatch(selector, "[^/]+") do
    local n = tonumber(w)
    if n then
       env = env[n]
    else
       env = env[w]
    end
  end
  return env
end

local function gen_substitution_no_args()
   return [[
	 if type(selector) == 'function' then
	    insert(out, tostring(selector()))
	 else
	    insert(out, tostring(selector))
	 end
   ]]
end

local function gen_substitution_with_args(args)
   return [[
	 if type(selector) == 'function' then
	    selector = selector(]] .. args .. [[, false)
	 end
	 insert(out, tostring(selector))
   ]]
end

local function gen_subtemplate_with_args(ca, args, non_scoped)
   table.insert(ca, "for e in coroutine.wrap(selector)," .. args .. ",true do")
   if not non_scoped then
      table.insert(ca, "  setmetatable(e, { __index = env })")
   end
   table.insert(ca, "  insert(out, subtemplates[rawget(e, '_template') or 1](e))")
   table.insert(ca, "end")
end

local function gen_subtemplate_no_args_table_selector(ca, non_scoped)
   table.insert(ca, "  for _, e in ipairs(selector) do")
   if not non_scoped then
      table.insert(ca, "  setmetatable(e, { __index = env })")
   end
   table.insert(ca, "    insert(out, subtemplates[rawget(e, '_template') or 1](e))")
   table.insert(ca, "  end")
end

local function gen_subtemplate_no_args_func_selector(ca, non_scoped)
   table.insert(ca, "  for e in coroutine.wrap(selector), nil, true do")
   if not non_scoped then
      table.insert(ca, "  setmetatable(e, { __index = env })")
   end
   table.insert(ca, "    insert(out, subtemplates[rawget(e, '_template') or 1](e))")
   table.insert(ca, "  end")
end

local function compile_text(text)
   return "insert(out, " .. string.format("%q", text) .. ")"
end

local function compile_template_application(selector, args, first_subtemplate, 
					    subtemplates)
   subtemplates = subtemplates or {}
   if first_subtemplate ~= "" then table.insert(subtemplates, 1, first_subtemplate) end
   local cs = parse_selector(selector)
   local ca = { "local selector = " .. cs }
   table.insert(ca, "if not selector then selector = '" .. selector .. "' end")
   if #subtemplates == 0 then
      if args ~= "" then
	 table.insert(ca, gen_substitution_with_args(args))
      else
	 table.insert(ca, gen_substitution_no_args())
      end
   else
      table.insert(ca, "local subtemplates = {}")
      for i, subtemplate in ipairs(subtemplates) do
	 table.insert(ca, "subtemplates[" .. i .. "] = cosmo.compile(" .. 
		      subtemplate .. "," .. tostring(non_scoped) .. ")")
      end
      if args ~= "" then
	 gen_subtemplate_with_args(ca, args, non_scoped)
      else
	 table.insert(ca, "if type(selector) == 'table' then")
	 gen_subtemplate_no_args_table_selector(ca, non_scoped)
	 table.insert(ca, "else")
	 gen_subtemplate_no_args_func_selector(ca, non_scoped)
	 table.insert(ca, "end")
      end
   end
   return table.concat(ca, "\n")
end

local function compile_template(compiled_parts)
   table.insert(compiled_parts, 1, [[
      return function (env)
		local concat = table.concat
		local insert = table.insert
		local out = {}
		if type(env) == "string" then env = { it = env } end
   ]])
   table.insert(compiled_parts, [[
	        return concat(out)
             end
   ]])
   local template_code = table.concat(compiled_parts, "\n")
   local template_func, err = loadstring(template_code, chunkname)
   if not template_func then
      error("syntax error when compiling template: " .. err)
   else
      setfenv(template_func, { table = table, ipairs = ipairs,
		 type = type, cosmo = _M, error = error, 
		 tostring = tostring, setmetatable = setmetatable,
	         coroutine = coroutine, rawget = rawget, print = print })
      return template_func()
   end
end

local compiler = grammar.cosmo_compiler{ text = compile_text,
   template_application = compile_template_application, 
   template = compile_template }

local cache_metatable =  { __index = function (tab, key)
					local new = {}
					tab[key] = new
					return new
				     end }

local cache_non_scoped = {}
setmetatable(cache_non_scoped, cache_metatable)

local cache_scoped = {}
setmetatable(cache_scoped, cache_metatable)

function compile(template, chunkname, non_scoped)
  local start = template:match("^(%[=*%[)")
  if start then template = template:sub(#start + 1, #template - #start) end
  if type(chunkname) == "boolean" then
     non_scoped, chunkname = chunkname, non_scoped
  end
  chunkname = chunkname or template
  local compiled_template
  if non_scoped then
     compiled_template = cache_non_scoped[template][chunkname]
  else
     compiled_template = cache_scoped[template][chunkname]
  end
  if not compiled_template then
    _M.non_scoped = non_scoped
    _M.chunkname = chunkname
    compiled_template = compiler:match(template)
    if non_scoped then
       cache_non_scoped[template][chunkname] = compiled_template
    else
       cache_scoped[template][chunkname] = compiled_template
    end
  end
  return compiled_template
end

local filled_templates = {}

local insert = table.insert
local concat = table.concat

local function fill_text(state, text)
   insert(state.out, text)
end

local function fill_template_application(state, selector, args, first_subtemplate, 
					 subtemplates)
   local env, out = state.env, state.out
   subtemplates = subtemplates or {}
   if first_subtemplate ~= "" then table.insert(subtemplates, 1, first_subtemplate) end
   selector = get_selector(env, selector) or selector
   if #subtemplates == 0 then
      if args ~= "" then
	 if type(selector) == 'function' then
	    selector = selector(dostring("return " .. args), false)
	 end
	 insert(out, tostring(selector))
      else
	 if type(selector) == 'function' then
	    insert(out, tostring(selector()))
	 else
	    insert(out, tostring(selector))
	 end
      end
   else
      if args ~= "" then
	 args = dostring("return " .. args)
	 for e in coroutine.wrap(selector), args, true do
	    setmetatable(e, { __index = env })
	    insert(out, fill(subtemplates[rawget(e, '_template') or 1], e))
	 end
      else
	 if type(selector) == 'table' then
	    for _, e in ipairs(selector) do
	       setmetatable(e, { __index = env })
	       insert(out, fill(subtemplates[rawget(e, '_template') or 1], e))
	    end
	 else
	    for e in coroutine.wrap(selector), nil, true do
	       setmetatable(e, { __index = env })
	       insert(out, fill(subtemplates[rawget(e, '_template') or 1], e))
	    end
	 end
      end
   end
end

local function fill_template(state, compiled_parts)
   return concat(state.out)
end

local interpreter = grammar.cosmo_compiler{ text = fill_text,
   template_application = fill_template_application, 
   template = fill_template }

function fill(template, env)
   local start = template:match("^(%[=*%[)")
   if start then template = template:sub(#start + 1, #template - #start) end
   if filled_templates[template] then return compile(template)(env) end
   filled_templates[template] = true
   local out = {}
  
   if type(env) == "string" then env = { it = env } end
   return interpreter:match(template, 1, { env = env, out = out })
end

local nop = function () end

function cond(bool, table)
   if bool then
      return function () yield(table) end
   else
      return nop
   end
end

f = compile

function c(bool)
   if bool then 
      return function (table)
		return function () yield(table) end
	     end
   else
      return function (table) return nop end
   end
end

yield = coroutine.yield

function freeze(template)
   return string.dump(template)
end

function thaw(frozen_template)
   local template_func = loadstring(frozen_template)
   setfenv(template_func, { table = table, ipairs = ipairs,
	      type = type, cosmo = _M, error = error, 
	      tostring = tostring, setmetatable = setmetatable,
	      coroutine = coroutine, rawget = rawget, print = print })
   return template_func
end
