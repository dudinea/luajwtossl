luajwtossl
===========

JSON Web Tokens for Lua


## Important notice

This is a pre alpha development version, please do not try to use it in production!!! Specifically, it 
contains an unmitigated security vulnerability.

```bash
$ sudo luarocks install --server=http://rocks.moonscript.org luajwtossl
```
## Master branch build status: ![build status](https://travis-ci.org/dudinea/luajwtossl.svg?branch=master)

## Usage

Basic usage:

```lua
local jwt = require "luajwtossl"

local key = "example_key"

local payload = {
	iss = "12345678",
	nbf = os.time(),
	exp = os.time() + 3600,
}

-- encode
local alg = "HS256" -- (default)
local token, err = jwt.encode(payload, key, alg)

-- token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiIx(cutted)...

-- decode and validate
local validate = true -- validate signature, exp and nbf (default: true)
local decoded, err = jwt.decode(token, key, validate)

-- decoded: { ["iss"] = 12345678, ["nbf"] = 1405108000, ["exp"] = 1405181916 }

-- only decode
local unsafe, err = jwt.decode(token)

-- unsafe:  { ["iss"] = 12345678, ["nbf"] = 1405108000, ["exp"] = 1405181916 }

```

An openresty/nginx lua jwt auth example:

```
# nginx.conf
location /auth {
	content_by_lua '
		local jwt = require "luajwtossl"

		local args = ngx.req.get_uri_args(1)

		if not args.jwt then

			return ngx.say("Where is token?")
		end

		local key = "SECRET"

		local ok, err = jwt.decode(args.jwt, key)

		if not ok then

			return ngx.say("Error: ", err)
		end

		ngx.say("Welcome!")
	';
}
```

Generate token and try:

```bash
$ curl your.server/auth?jwt=TOKEN
```

## Algorithms

**HMAC**

* HS256	- HMAC using SHA-256 hash algorithm (default)
* HS384	- HMAC using SHA-384 hash algorithm
* HS512 - HMAC using SHA-512 hash algorithm

## License
MIT
