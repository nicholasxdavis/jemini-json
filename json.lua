-- ==========================================================
-- ROBUST JSON PARSER
-- Enhanced for Stability and Error Reporting
-- ==========================================================
local json = {}

-- Utility: Determine variable type (array vs object)
local function kind_of(obj)
  if type(obj) ~= 'table' then return type(obj) end
  local i = 1
  for _ in pairs(obj) do
    if obj[i] ~= nil then i = i + 1 else return 'table' end
  end
  if i == 1 then return 'table' else return 'array' end
end

-- Utility: Escape strings for JSON output
local function escape_str(s)
  local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
  local out_char = {'\\', '"', '/',  'b',  'f',  'n',  'r',  't'}
  for i, c in ipairs(in_char) do
    s = s:gsub(c, '\\' .. out_char[i])
  end
  return s
end

-- Utility: Skip whitespace and delimiters
local function skip_delim(str, pos, delim, err_if_missing)
  pos = pos + #str:match('^%s*', pos)
  if str:sub(pos, pos) ~= delim then
    if err_if_missing then error('JSON Error: Expected ' .. delim .. ' near position ' .. pos) end
    return pos, false
  end
  return pos + 1, true
end

-- Parse String Value
local function parse_str_val(str, pos, val)
  val = val or ''
  local early_end_error = 'JSON Error: End of input found while parsing string.'
  if pos > #str then error(early_end_error) end
  
  local c = str:sub(pos, pos)
  
  if c == '"' then return val, pos + 1 end
  
  if c ~= '\\' then 
      return parse_str_val(str, pos + 1, val .. c) 
  end
  
  -- Handle Escapes
  local esc_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/'}
  local nextc = str:sub(pos + 1, pos + 1)
  if not nextc then error(early_end_error) end
  
  -- Handle Unicode (basic \uXXXX support could be added here, currently skipping raw)
  return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Parse Number Value
local function parse_num_val(str, pos)
  local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
  local val = tonumber(num_str)
  if not val then error('JSON Error: Invalid number at position ' .. pos) end
  return val, pos + #num_str
end

-- Recursive Value Parser
local function parse_val(str, pos)
  pos = pos + #str:match('^%s*', pos)
  local c = str:sub(pos, pos)
  
  if c == '' then error('JSON Error: Unexpected end of input') end

  if c == '{' then -- Object
    local obj = {}
    pos = pos + 1
    while true do
      pos = pos + #str:match('^%s*', pos)
      if str:sub(pos, pos) == '}' then return obj, pos + 1 end
      local key; key, pos = parse_str_val(str, pos + 1)
      pos = skip_delim(str, pos, ':', true)
      obj[key], pos = parse_val(str, pos)
      pos, _ = skip_delim(str, pos, ',')
    end
  elseif c == '[' then -- Array
    local arr = {}
    pos = pos + 1
    local idx = 1
    while true do
      pos = pos + #str:match('^%s*', pos)
      if str:sub(pos, pos) == ']' then return arr, pos + 1 end
      arr[idx], pos = parse_val(str, pos)
      idx = idx + 1
      pos, _ = skip_delim(str, pos, ',')
    end
  elseif c == '"' then return parse_str_val(str, pos + 1)
  elseif c == '-' or c:match('%d') then return parse_num_val(str, pos)
  elseif str:sub(pos, pos + 3) == 'true' then return true, pos + 4
  elseif str:sub(pos, pos + 4) == 'false' then return false, pos + 5
  elseif str:sub(pos, pos + 3) == 'null' then return nil, pos + 4
  else error('JSON Error: Unknown token "' .. c .. '" at position ' .. pos) end
end

-- PUBLIC DECODE
function json.decode(str)
  if type(str) ~= 'string' then 
      return nil, 'Expected argument of type string, got ' .. type(str) 
  end
  
  -- === BOM REMOVAL ===
  -- Removes invisible characters that Windows sometimes adds to the start of files
  if str:sub(1, 3) == "\239\187\191" then
      str = str:sub(4)
  end
  
  -- === SAFE DECODE ===
  local status, res = pcall(parse_val, str, 1)
  
  if status then
      return res
  else
      return nil, res -- Return nil and the error message
  end
end

-- PUBLIC ENCODE
function json.encode(val)
    if type(val) == "table" then
        local kind = kind_of(val)
        if kind == "array" then
            local res = "["
            for i, v in ipairs(val) do
                res = res .. json.encode(v)
                if i < #val then res = res .. "," end
            end
            return res .. "]"
        else
            local res = "{"
            local keys = {}
            for k in pairs(val) do table.insert(keys, k) end
            table.sort(keys) -- Consistent ordering
            for i, k in ipairs(keys) do
                res = res .. '"' .. escape_str(tostring(k)) .. '":' .. json.encode(val[k])
                if i < #keys then res = res .. "," end
            end
            return res .. "}"
        end
    elseif type(val) == "string" then
        return '"' .. escape_str(val) .. '"'
    elseif type(val) == "number" or type(val) == "boolean" then
        return tostring(val)
    else
        return "null"
    end
end

return json