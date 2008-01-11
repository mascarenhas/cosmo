local require = require

local lpeg = require "lpeg"
local re = require "luma.re"

local loadstring = loadstring

module(..., package.seeall)

local function parse_selector(selector)
  selector = string.sub(selector, 2, #selector)
  local parts = {}
  for w in string.gmatch(selector, "[^%.]+") do
    local n = tonumber(w)
    if n then
      table.insert(parts, "[" .. n .. "]")
    else
      table.insert(parts, "['" .. w .. "']")
    end
  end
  return "env" .. table.concat(parts)
end

local start = "[" * lpeg.P"="^0 * "["

local longstring = lpeg.P(function (s, i)
  local l = lpeg.match(start, s, i)
  if not l then return nil end
  local p = lpeg.P("]" .. string.rep("=", l - i - 2) .. "]")
  p = (1 - p)^0 * p
  return lpeg.match(p, s, l)
end)

longstring = #("[" * lpeg.S"[=") * longstring

local alpha =  lpeg.R('__','az','AZ','\127\255') 
local n = lpeg.R'09'
local alphanum = alpha + n

local number = (lpeg.P'.' + n)^1 * (lpeg.S'eE' * lpeg.S'+-'^-1)^-1 * (alphanum)^0
number = #(n + (lpeg.P'.' * n)) * number

local shortstring = (lpeg.P'"' * ( (lpeg.P'\\' * 1) + (1 - (lpeg.S'"\n\r\f')) )^0 * lpeg.P'"') +
  (lpeg.P"'" * ( (lpeg.P'\\' * 1) + (1 - (lpeg.S"'\n\r\f")) )^0 * lpeg.P"'")

local space = (lpeg.S'\n \t\r\f')^0
 
local syntax = [[
  template <- (item* -> {} !.) -> compile_template
  item <- text / templateappl
  text <- {~ (!selector ('$$' -> '$' / .))+ ~} -> compile_text
  selector <- '$' alphanum+ ('.' alphanum+)*
  templateappl <- ({selector} {args?} {longstring?}) -> compile_application
  args <- '{' _ '}' / '{' _ arg _ (',' _ arg _)* ','? _ '}'
  arg <- attr / literal
  attr <- symbol _ '=' _ literal / '[' _ literal _ ']' _ '=' _ literal
  symbol <- alpha alphanum*
  literal <- args / string / number / 'true' / 'false' / 'nil'
]]

local recursive_match = false

local defs = {
  alpha = alpha,
  alphanum = alphanum,
  number = number,
  string = shortstring,
  longstring = longstring,
  ['_'] = space,
  compile_text = function (s)
		   return "table.insert(out, " .. string.format("%q", s) .. ")"
		 end,
  compile_application = function (selector, args, subt)
			  local cs = parse_selector(selector)
			  local ca = { "local selector = " .. cs }
			  table.insert(ca, "if not selector then selector = '' end")
			  if subt == "" then
			    if args ~= "" then
			      table.insert(ca, "selector = selector(" .. args .. ", false)")
 			      table.insert(ca, "table.insert(out, tostring(selector))")
			    else
			      table.insert(ca, "if type(selector) == 'function' then")
			      table.insert(ca, "  table.insert(out, tostring(selector()))")
			      table.insert(ca, "else")
			      table.insert(ca, "  table.insert(out, tostring(selector))")
			      table.insert(ca, "end")
                            end
			  else
			    table.insert(ca, "local subt = cosmo.compile(" .. subt .. "," .. 
			      tostring(recursive_match) .. ")")
			    if args ~= "" then
			      table.insert(ca, "for e in coroutine.wrap(selector)," .. args .. ",true do")
			      if recursive_match then
			        table.insert(ca, "  setmetatable(e, { __index = env })")
			      end
			      table.insert(ca, "  table.insert(out, subt(e))")
			      table.insert(ca, "end")
			    else
			      table.insert(ca, "if type(selector) == 'table' then")
			      table.insert(ca, "  for _, e in ipairs(selector) do")
			      if recursive_match then
			        table.insert(ca, "  setmetatable(e, { __index = env })")
			      end
			      table.insert(ca, "    table.insert(out, subt(e))")
			      table.insert(ca, "  end")
			      table.insert(ca, "else")
			      table.insert(ca, "  for e in coroutine.wrap(selector) do")
			      if recursive_match then
			        table.insert(ca, "  setmetatable(e, { __index = env })")
			      end
			      table.insert(ca, "    table.insert(out, subt(e))")
			      table.insert(ca, "  end")
			      table.insert(ca, "end")
			    end
			  end
			  return table.concat(ca, "\n")
			end,
  compile_template = function (ct)
		       table.insert(ct, 1, [[
			   local table, ipairs, type, cosmo, error, tostring = ...
			   return function (env)
				    local out = {}
				]])
		       table.insert(ct, [[
					  return table.concat(out)
				      end
				    ]])
		       local template_code = table.concat(ct, "\n")
		       local template_func, err = loadstring(template_code)
		       if not template_func then
			 error("syntax error when compiling template: " .. err)
		       else
			 return template_func(table, ipairs, type, _M, error, tostring)
		       end
		     end
}

local compiler = re.compile(syntax, defs)

function compile(template, recursive)
  recursive_match = recursive
  return compiler:match(template)
end

local compiled_templates = {}

function fill(template, env)
  local ct = compiled_templates[template]
  if not ct then 
    ct = compile(template)
    compiled_templates[template] = ct
  end
  return ct(env)
end

function cond(b, t)
  return function()
	   if b then
	     yield(t)
	   end
	 end
end

yield = coroutine.yield
