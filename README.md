## Tile38 leader-follower health check and status page using OpenResty
  
Spawns background timer-based "light threads" to perform periodic healthchecks on the Tile 38 servers specified in the NGINX upstream group. The healthchecker does not need any client traffic to function. 

Docker
------

A [Dockerfile](Dockerfile) is provided to build a Docker image of the health checker and status page:

> Note that :
> * The Docker image is based on the [OpenResty Official Docker Image]
> * OPM dependencies are installed during the building process (See below)


Docker Compose
--------------

A [docker-compose.yml](docker-compose.yml) file is also provided to orchestrate
three containers :

* The NGINX/Lua health checker (See below)
* A Tile38-leader server on port 9851
* A Tile38-follower server on port 9852 -  follow and replicate the leader's data


To start the environment, simply run :

```shell
docker-compose up -d --build
```

> The Docker image of the health check app is built before start due to `--build` option.

Status Page
---

To view the status page,  simply curl the page or open your browser :

```shell
curl http://localhost:8080/status
```
![status page](7EED6F2B-2F0E-4DF5-A228-EC3B0FA655D3_4_5005_c.jpeg?raw=true "Status page showing peers")


OPM (OpenResty package manager)
---

One library is installed during the Docker image building process 
(not actually used in this config, but useful when working with openresty):

* [lua-resty-http] : Lua HTTP client cosocket driver for OpenResty / ngx_lua.
https://github.com/ledgetech/lua-resty-http



Configuration
-------------

For demo purposes, everything is contained in the [nginx configuration file](conf/nginx.conf) :

```nginx
worker_processes  1;

error_log logs/error.log;

events {
    worker_connections 1024;
}

http {

    # define upstreams:
    upstream tile38-leader {
        server tile38-leader:9851;
    }
    upstream tile38-follower {
        server tile38-follower:9852;
    }

    # the size depends on the number of servers in upstream {}:
    lua_shared_dict healthcheck 1m;

    lua_socket_log_errors off;

    init_worker_by_lua_block {
        local hc = require "resty.upstream.healthcheck"

        local leader_ok, err = hc.spawn_checker{
            shm = "healthcheck",  -- defined by "lua_shared_dict"
            upstream = "tile38-leader", -- defined by "upstream"
            type = "http",

            http_req = "GET /healthz HTTP/1.0\r\nHost: tile38-leader\r\n\r\n",
                    -- raw HTTP request for checking

            interval = 2000,  -- run the check cycle every 2 sec
            timeout = 1000,   -- 1 sec is the timeout for network operations
            fall = 3,  -- # of successive failures before turning a peer down
            rise = 2,  -- # of successive successes before turning a peer up
            valid_statuses = {200},  -- a list valid HTTP status code
            concurrency = 10,  -- concurrency level for test requests
        }
        if not leader_ok then
            ngx.log(ngx.ERR, "failed to spawn tile38-leader health checker: ", err)
            return
        end

        local follower_ok, err = hc.spawn_checker{
            shm = "healthcheck",  -- defined by "lua_shared_dict"
            upstream = "tile38-follower", -- defined by "upstream"
            type = "http",

            http_req = "GET /status HTTP/1.0\r\nHost: tile38-follower\r\n\r\n",
                    -- raw HTTP request for checking

            interval = 2000,  -- run the check cycle every 2 sec
            timeout = 1000,   -- 1 sec is the timeout for network operations
            fall = 3,  -- # of successive failures before turning a peer down
            rise = 2,  -- # of successive successes before turning a peer up
            valid_statuses = {200},  -- a list valid HTTP status code
            concurrency = 10,  -- concurrency level for test requests
        }
        if not follower_ok then
            ngx.log(ngx.ERR, "failed to spawn tile38-follower health checker: ", err)
            return
        end
    }

    server {
        listen 8080;
    
         # default page:
        location / {
            default_type text/html;
            content_by_lua_block {
                ngx.say("<p>hello, world</p>")
            }
        }

        # status page for all the peers:
        location = /status {
            access_log off;
            default_type text/plain;
            content_by_lua_block {
                local hc = require "resty.upstream.healthcheck"
                ngx.say("Upstream healthcheck for geospatial services")
                ngx.say("Nginx Worker PID: ", ngx.worker.pid())
                ngx.print(hc.status_page())
            }
        }
    }
}
```


