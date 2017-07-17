--[[lit-meta
  name = "creationix/weblit-server"
  version = "3.0.0"
  dependencies = {
    'creationix/coro-net@3.0.0',
    'luvit/http-codec@3.0.0'
  }
  description = "Weblit is a webapp framework designed around routes and middleware layers."
  tags = {"weblit", "server", "framework"}
  license = "MIT"
  author = { name = "Tim Caswell" }
  homepage = "https://github.com/creationix/weblit/blob/master/libs/weblit-app.lua"
]]

local createServer = require('coro-net').createServer
local httpCodec = require('http-codec')

-- Provide a nice case insensitive interface to headers.
local headerMeta = {}
function headerMeta:__index(name)
  if type(name) ~= "string" then
    return rawget(self, name)
  end
  name = name:lower()
  for i = 1, #self do
    local key, value = unpack(self[i])
    if key:lower() == name then return value end
  end
end
function headerMeta:__newindex(name, value)
  -- non-string keys go through as-is.
  if type(name) ~= "string" then
    return rawset(self, name, value)
  end
  -- First remove any existing pairs with matching key
  local lowerName = name:lower()
  for i = #self, 1, -1 do
    if self[i][1]:lower() == lowerName then
      table.remove(self, i)
    end
  end
  -- If value is nil, we're done
  if value == nil then return end
  -- Otherwise, set the key(s)
  if (type(value) == "table") then
    -- We accept a table of strings
    for i = 1, #value do
      rawset(self, #self + 1, {name, tostring(value[i])})
    end
  else
    -- Or a single value interperted as string
    rawset(self, #self + 1, {name, tostring(value)})
  end
end

local function newServer(run)
  local server = {}
  local bindings = {}

  run = run or function () end

  local function handleRequest(head, input, socket)
    local req = {
      socket = socket,
      method = head.method,
      path = head.path,
      headers = setmetatable({}, headerMeta),
      version = head.version,
      keepAlive = head.keepAlive,
      body = input
    }
    for i = 1, #head do
      req.headers[i] = head[i]
    end

    local res = {
      code = 404,
      headers = setmetatable({}, headerMeta),
      body = "Not Found\n",
    }

    local success, err = pcall(function ()
      run(req, res, function() end)
    end)
    if not success then
      res.code = 500
      res.headers = setmetatable({}, headerMeta)
      res.body = err
      print(err)
    end

    local out = {
      code = res.code,
      keepAlive = res.keepAlive,
    }
    for i = 1, #res.headers do
      out[i] = res.headers[i]
    end
    return out, res.body, res.upgrade
  end

  local function handleConnection(read, write, socket, updateDecoder, updateEncoder)

    for head in read do
      local parts = {}
      for chunk in read do
        if #chunk > 0 then
          parts[#parts + 1] = chunk
        else
          break
        end
      end
      local res, body, upgrade = handleRequest(head, #parts > 0 and table.concat(parts) or nil, socket)
      write(res)
      if upgrade then
        return upgrade(read, write, updateDecoder, updateEncoder, socket)
      end
      write(body)
      if not (res.keepAlive and head.keepAlive) then
        break
      end
    end
    write()

  end

  function server.setRun(newRun)
    run = newRun
  end

  function server.bind(options)
    if not options.host then
      options.host = "127.0.0.1"
    end
    if not options.port then
      local getuid = require('uv').getuid
      options.port = (getuid and getuid() == 0) and
        (options.tls and 443 or 80) or
        (options.tls and 8443 or 8080)
    end
    bindings[#bindings + 1] = options
    return server
  end

  function server.start()
    if #bindings == 0 then
      server.bind({})
    end
    for i = 1, #bindings do
      local options = bindings[i]
      options.decode = httpCodec.decoder()
      options.encode = httpCodec.encoder()
      createServer(options, handleConnection)
      print("HTTP server listening at http" .. (options.tls and "s" or "") ..
            "://" .. options.host .. (options.port == (options.tls and 443 or 80)
            and "" or ":" .. options.port) .. "/")
    end
    return server
  end

  return server
end

return {
  newServer = newServer,
  handleRequest = handleRequest,
  handleConnection = handleConnection,
  headerMeta = headerMeta
}
