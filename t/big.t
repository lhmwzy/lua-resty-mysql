# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (2 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    resolver \$TEST_NGINX_RESOLVER;
    lua_package_path "$pwd/lib/?.lua;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;
$ENV{TEST_NGINX_MYSQL_HOST} ||= '127.0.0.1';
$ENV{TEST_NGINX_MYSQL_PATH} ||= '/var/run/mysql/mysql.sock';

log_level 'warn';

no_long_string();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: big field value exceeding 256
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local cjson = require "cjson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(1024))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate = db:query("insert into cats (name) value (\'"
                   .. string.rep("B", 1024)
                   .. "\')")

            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table cats (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate = db:query("select * from cats order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", cjson.encode(res))

            res, err, errno, sqlstate = db:query("select * from cats order by id desc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", cjson.encode(res))

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body eval
'connected to mysql.
table cats dropped.
table cats created.
1 rows inserted into table cats (last id: 1)
result: [{"name":"' . ('B' x 1024)
   . '","id":1}]' . "\n" .
'result: [{"name":"' . ('B' x 1024)
   . '","id":1}]' . "\n"



=== TEST 2: big field value exceeding max packet size
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local cjson = require "cjson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                max_packet_size = 1024 })

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(1024))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate = db:query("insert into cats (name) value (\'"
                   .. string.rep("B", 1024)
                   .. "\')")

            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table cats (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate = db:query("select * from cats order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", cjson.encode(res))

            res, err, errno, sqlstate = db:query("select * from cats order by id desc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", cjson.encode(res))

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body eval
'connected to mysql.
table cats dropped.
table cats created.
1 rows inserted into table cats (last id: 1)
bad result: packet size too big: 1029: nil: nil.
'

