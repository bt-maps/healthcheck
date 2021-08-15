FROM openresty/openresty:alpine
# add Lua HTTP client cosocket driver from opm
RUN apk add --no-cache curl perl \
  && opm get ledgetech/lua-resty-http
# copy config and lua directories to container
COPY . /usr/local/openresty/nginx
