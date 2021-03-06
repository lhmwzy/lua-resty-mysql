# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

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

=== TEST 1: bad user
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "user_not_found",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            db:close()
        ';
    }
--- request
GET /t
--- response_body
failed to connect: Access denied for user 'user_not_found'@'localhost' (using password: YES): 1045 28000
--- no_error_log
[error]



=== TEST 2: bad host
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "host-not-found.org",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            db:close()
        ';
    }
--- request
GET /t
--- response_body_like chop
^failed to connect: failed to connect: host-not-found.org could not be resolved(?: \(3: Host not found\))?: nil nil$
--- no_error_log
[error]
--- timeout: 5



=== TEST 3: connected
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
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

            ngx.say("connected to mysql ", db:server_ver())

            db:close()
        ';
    }
--- request
GET /t
--- response_body_like
connected to mysql \d\.\S+
--- no_error_log
[error]



=== TEST 4: send query w/o result set
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
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

            ngx.say("connected to mysql ", db:server_ver(), ".")

            local bytes, err = db:send_query("drop table if exists cats")
            if not bytes then
                ngx.say("failed to send query: ", err)
            end

            ngx.say("sent ", bytes, " bytes.")

            local res, err, errno, sqlstate = db:read_result()
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
            end

            local cjson = require "cjson"
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
--- response_body_like chop
^connected to mysql \d\.\S+\.
sent 30 bytes\.
result: (?:{"insert_id":0,"server_status":2,"warning_count":1,"affected_rows":0}|{"affected_rows":0,"insert_id":0,"server_status":2,"warning_count":[01]})$
--- no_error_log
[error]



=== TEST 5: send bad query
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
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

            ngx.say("connected to mysql ", db:server_ver(), ".")

            local bytes, err = db:send_query("bad SQL")
            if not bytes then
                ngx.say("failed to send query: ", err)
            end

            ngx.say("sent ", bytes, " bytes.")

            local res, err, errno, sqlstate = db:read_result()
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            local cjson = require "cjson"
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
--- response_body_like chop
^connected to mysql \d\.\S+\.
sent 12 bytes\.
bad result: You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near 'bad SQL' at line 1: 1064: 42000\.$
--- no_error_log
[error]



=== TEST 6: select query with an non-empty result set
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

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(5))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate = db:query("insert into cats (name) value (\'Bob\'),(\'\'),(null)")
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
--- response_body
connected to mysql.
table cats dropped.
table cats created.
3 rows inserted into table cats (last id: 1)
result: [{"name":"Bob","id":1},{"name":"","id":2},{"name":null,"id":3}]
result: [{"name":null,"id":3},{"name":"","id":2},{"name":"Bob","id":1}]
--- no_error_log
[error]



=== TEST 7: select query with an empty result set
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

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(5))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

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
--- response_body
connected to mysql.
table cats dropped.
table cats created.
result: {}
result: {}
--- no_error_log
[error]



=== TEST 8: numerical types
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

            local res, err, errno, sqlstate = db:query("drop table if exists foo")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table foo dropped.")

            res, err, errno, sqlstate = db:query("create table foo (id serial primary key, bar tinyint, baz smallint, bah float, blah double, kah bigint, hah mediumint, haha year, lah int)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table foo created.")

            res, err, errno, sqlstate = db:query("insert into foo (bar, baz, bah, blah, kah, hah, haha, lah) value (3, 4, 3.14, 5.16, 65535, 256, 1998, 579),(null, null, null, null, null, null, null, null)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table foo (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate = db:query("select * from foo order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", cjson.encode(res))

            res, err, errno, sqlstate = db:query("select * from foo order by id desc")
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
--- response_body
connected to mysql.
table foo dropped.
table foo created.
2 rows inserted into table foo (last id: 1)
result: [{"id":1,"hah":256,"kah":65535,"lah":579,"haha":1998,"bah":3.14,"blah":5.16,"baz":4,"bar":3},{"id":2,"hah":null,"kah":null,"lah":null,"haha":null,"bah":null,"blah":null,"baz":null,"bar":null}]
result: [{"id":2,"hah":null,"kah":null,"lah":null,"haha":null,"bah":null,"blah":null,"baz":null,"bar":null},{"id":1,"hah":256,"kah":65535,"lah":579,"haha":1998,"bah":3.14,"blah":5.16,"baz":4,"bar":3}]
--- no_error_log
[error]
--- timeout: 5



=== TEST 9: multiple DDL statements
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

            local res, err, errno, sqlstate =
                db:query("drop table if exists foo; "
                         .. "create table foo (id serial primary key, name text);")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", cjson.encode(res), ", err:", err)

            res, err, errno, sqlstate =
                db:query("select * from cats order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
            else
                ngx.say("result: ", cjson.encode(res), ", err:", err)
            end

            res, err, errno, sqlstate = db:read_result()
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
            else
                ngx.say("result: ", cjson.encode(res), ", err:", err)
            end

            res, err, errno, sqlstate =
                db:query("select * from cats order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
            else
                ngx.say("result: ", cjson.encode(res), ", err:", err)
            end

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body
connected to mysql.
result: {"affected_rows":0,"insert_id":0,"server_status":10,"warning_count":0}, err:again
bad result: failed to send query: cannot send query in the current context: 2: nil: nil.
result: {"affected_rows":0,"insert_id":0,"server_status":2,"warning_count":0}, err:nil
result: {}, err:nil
--- no_error_log
[error]



=== TEST 10: multiple select queries
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

            local res, err, errno, sqlstate =
                db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")

            res, err, errno, sqlstate =
                db:query("create table cats "
                         .. "(id serial primary key, name varchar(5))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate =
                db:query("insert into cats (name) "
                         .. "values (\'Bob\'),(\'\'),(null)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows .. " rows inserted into table cats (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate =
                db:query("select * from cats order by id asc; "
                         .. "select * from cats order by id desc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", cjson.encode(res), ", err:", err)

            res, err, errno, sqlstate = db:read_result()
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", cjson.encode(res), ", err:", err)

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body
connected to mysql.
table cats dropped.
table cats created.
3 rows inserted into table cats (last id: 1)
result: [{"name":"Bob","id":1},{"name":"","id":2},{"name":null,"id":3}], err:again
result: [{"name":null,"id":3},{"name":"","id":2},{"name":"Bob","id":1}], err:nil
--- no_error_log
[error]



=== TEST 11: set_keepalive in the wrong state
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

            local res, err, errno, sqlstate =
                db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")

            res, err, errno, sqlstate =
                db:query("create table cats "
                         .. "(id serial primary key, name varchar(5))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate =
                db:query("insert into cats (name) "
                         .. "values (\'Bob\'),(\'\'),(null)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows .. " rows inserted into table cats (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate =
                db:query("select * from cats order by id asc; "
                         .. "select * from cats order by id desc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", cjson.encode(res), ", err:", err)

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body
connected to mysql.
table cats dropped.
table cats created.
3 rows inserted into table cats (last id: 1)
result: [{"name":"Bob","id":1},{"name":"","id":2},{"name":null,"id":3}], err:again
failed to set keepalive: cannot be reused in the current connection state: 2
--- no_error_log
[error]



=== TEST 12: set keepalive
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

            ngx.say("connected to mysql: ", db:get_reused_times())

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end

ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            ngx.say("connected to mysql: ", db:get_reused_times())

            res, err, errno, sqlstate =
                db:query("select * from cats order by id asc;")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", cjson.encode(res), ", err:", err)

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body_like chop
^connected to mysql: [02]
connected to mysql: [13]
result: \[{"name":"Bob","id":1},{"name":"","id":2},{"name":null,"id":3}\], err:nil$
--- no_error_log
[error]



=== TEST 13: send query w/o result set (unix domain socket)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql ", db:server_ver(), ".")

            local bytes, err = db:send_query("drop table if exists cats")
            if not bytes then
                ngx.say("failed to send query: ", err)
            end

            ngx.say("sent ", bytes, " bytes.")

            local res, err, errno, sqlstate = db:read_result()
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
            end

            local cjson = require "cjson"
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
--- response_body_like chop
^connected to mysql \d\.\S+\.
sent 30 bytes\.
result: (?:{"insert_id":0,"server_status":2,"warning_count":1,"affected_rows":0}|{"affected_rows":0,"insert_id":0,"server_status":2,"warning_count":[01]})$
--- no_error_log
[error]

