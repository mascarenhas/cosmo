
local lpeg = require "cosmo.lpeg"
local re = require "cosmo.re"

module(..., package.seeall)

function parse_selector(selector, env)
  env = env or "env"
  selector = string.sub(selector, 2, #selector)
  local parts = {}
  for w in string.gmatch(selector, "[^|]+") do
    local n = tonumber(w)
    if n then
      table.insert(parts, "[" .. n .. "]")
    else
      table.insert(parts, "['" .. w .. "']")
    end
  end
  return env .. table.concat(parts)
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
  selector <- '$' alphanum+ ('|' alphanum+)*
  templateappl <- ({selector} {~args?~} {longstring?} (_ ','_ {longstring})* -> {}) -> compile_application
  args <- '{' _ '}' / '{' _ arg _ (',' _ arg _)* ','? _ '}'
  arg <- attr / literal
  attr <- symbol _ '=' _ literal / '[' _ literal _ ']' _ '=' _ literal
  symbol <- alpha alphanum*
  literal <- args / string / number / 'true' / 'false' / 'nil' / {selector} -> parse_selector
]]

local syntax_defs = {
  alpha = alpha,
  alphanum = alphanum,
  number = number,
  string = shortstring,
  longstring = longstring,
  ['_'] = space,
  parse_selector = function (state, selector)
		      selector = selector or state
		      return parse_selector(selector)
		   end
}

function cosmo_compiler(compiler_funcs)
   syntax_defs.compile_template = compiler_funcs.template
   syntax_defs.compile_text = compiler_funcs.text
   syntax_defs.compile_application = compiler_funcs.template_application
   return re.compile(syntax, syntax_defs)
end
