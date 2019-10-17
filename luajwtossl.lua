local cjson  = require 'cjson'
local base64 = require 'base64'
local hmac   = require 'openssl.hmac'
local pkey   = require 'openssl.pkey'
local x509   = require 'openssl.x509'
local digest = require 'openssl.digest'

local function mkosslobj(fun, str, format)
   local result, value =  pcall( function ()
	 return fun(str, format)
   end)
   if result then
      return value, nil
   else
      return nil, value
   end
end

local function extract_x509_cert(str)
   return mkosslobj(x509.new, str, "*")
end

local function extract_privkey(str)
   return  mkosslobj(pkey.new, str, "*")
end

local function extract_pubkey(str)
   local pubkey = mkosslobj(pkey.new, str, "*")
   if not pubkey then
      local crt = extract_x509_cert(str);
      if crt then
		 pubkey = crt:getPublicKey()
      end
   end
   return pubkey
end

local function mkdigest(data, alg)
   local md  = digest.new(alg)
   assert(md, "failed to create " .. alg .. " message digest")
   md = md:update(data)
   -- Note: Do not call md:final here!!
   -- final() is not idempotent and is being
   -- called implicitly while performing signature
   -- or verification
   return md
end

local function mk_hmac_sign_fun(alg)
   local fun = function (data, key)
      local hd = hmac.new(key , alg)
      hd:update(data)
      return hd:final()
   end
   return fun
end

local function mk_hmac_verify_fun(alg)
   local fun = function (data, key)
      local hd = hmac.new(key , alg)
      hd:update(data)
      return hd:final()
   end
   return fun
end

local function mk_pubkey_sign_fun(alg)
   return function (data, key)
	  local priv = extract_privkey(key)
	  assert(priv, "failed to get private key from provided argument:" ..
				"must be private key in pem or in der format")
	  local md  = mkdigest(data, alg)
	  local signature = priv:sign(md)
	  return signature
   end
end

local function mk_pubkey_verify_fun(alg)
   return function(data, signature, key)
	  local pubkey = extract_pubkey(key)
	  assert(pubkey, "failed to get public key from provided argument:" ..
				"must be public key or x509 certificate in pem or der formats")
	  local md  = mkdigest(data, alg)
	  return  pubkey:verify(signature, md)
   end
end

local alg_sign = {
   ['HS256'] = mk_hmac_sign_fun('sha256'),
   ['HS384'] = mk_hmac_sign_fun('sha384'),
   ['HS512'] = mk_hmac_sign_fun('sha512'),
   ['RS256'] = mk_pubkey_sign_fun('sha256'),
   ['RS384'] = mk_pubkey_sign_fun('sha384'),
   ['RS512'] = mk_pubkey_sign_fun('sha512')
}

local alg_verify = {
   ['HS256'] = function(data, signature, key) return signature == alg_sign['HS256'](data, key) end,
   ['HS384'] = function(data, signature, key) return signature == alg_sign['HS384'](data, key) end,
   ['HS512'] = function(data, signature, key) return signature == alg_sign['HS512'](data, key) end,
   ['RS256'] = mk_pubkey_verify_fun('sha256'),
   ['RS384'] = mk_pubkey_verify_fun('sha384'),
   ['RS512'] = mk_pubkey_verify_fun('sha512')
}

local function b64_encode(input)
   local result = base64.encode(input)

   result = result:gsub('+','-'):gsub('/','_'):gsub('=','')

   return result
end

local function b64_decode(input)
   --   input = input:gsub('\n', ''):gsub(' ', '')

   local reminder = #input % 4

   if reminder > 0 then
      local padlen = 4 - reminder
      input = input .. string.rep('=', padlen)
   end

   input = input:gsub('-','+'):gsub('_','/')

   return base64.decode(input)
end

local function tokenize(str, div, len)
   local result, pos = {}, 0

   for st, sp in function() return str:find(div, pos, true) end do

      result[#result + 1] = str:sub(pos, st-1)
      pos = sp + 1

      len = len - 1

      if len <= 1 then
         break
      end
   end

   result[#result + 1] = str:sub(pos)

   return result
end

local M = {}

function M.encode(data, key, alg)
   if type(data) ~= 'table' then return nil, "Argument #1 must be table" end
   if type(key) ~= 'string' then return nil, "Argument #2 must be string" end

   alg = alg or "HS256" 

   if not alg_sign[alg] then
      return nil, "Algorithm not supported"
   end

   local header = { typ='JWT', alg=alg }

   local segments = {
      b64_encode(cjson.encode(header)),
      b64_encode(cjson.encode(data))
   }

   local signing_input = table.concat(segments, ".")

   local signature = alg_sign[alg](signing_input, key)

   segments[#segments+1] = b64_encode(signature)

   return table.concat(segments, ".")
end

function M.decode(data, key, verify)
   if key and verify == nil then verify = true end
   if type(data) ~= 'string' then return nil, "Argument #1 must be string" end
   if verify and type(key) ~= 'string' then return nil, "Argument #2 must be string" end

   local token = tokenize(data, '.', 3)

   if #token ~= 3 then
      return nil, "Invalid token"
   end

   local headerb64, bodyb64, sigb64 = token[1], token[2], token[3]

   local ok, header, body, sig = pcall(function ()

         return cjson.decode(b64_decode(headerb64)), 
         cjson.decode(b64_decode(bodyb64)),
         b64_decode(sigb64)
   end) 

   if not ok then
      return nil, "Invalid json"
   end

   if verify then

      if not header.typ or header.typ ~= "JWT" then
         return nil, "Invalid typ"
      end

      if not header.alg or type(header.alg) ~= "string" then
         return nil, "Invalid alg"
      end

      if body.exp and type(body.exp) ~= "number" then
         return nil, "exp must be number"
      end

      if body.nbf and type(body.nbf) ~= "number" then
         return nil, "nbf must be number"
      end

      if not alg_verify[header.alg] then
         return nil, "Algorithm not supported"
      end

      if not alg_verify[header.alg](headerb64 .. "." .. bodyb64, sig, key) then
         return nil, "Invalid signature"
      end

      if body.exp and os.time() >= body.exp then
         return nil, "Not acceptable by exp"
      end

      if body.nbf and os.time() < body.nbf then
         return nil, "Not acceptable by nbf"
      end
   end

   return body
end

return M
