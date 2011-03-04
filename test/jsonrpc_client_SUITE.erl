%    __                        __      _
%   / /__________ __   _____  / /___  (_)___  ____ _
%  / __/ ___/ __ `/ | / / _ \/ / __ \/ / __ \/ __ `/
% / /_/ /  / /_/ /| |/ /  __/ / /_/ / / / / / /_/ /
% \__/_/   \__,_/ |___/\___/_/ .___/_/_/ /_/\__, /
%                           /_/            /____/
%
% Copyright (c) Travelping GmbH <info@travelping.com>

-module(jsonrpc_client_SUITE).

-compile(export_all).

-include("ct.hrl").
-define(HOST, "http://localhost:5671/rpc/example").

% ---------------------------------------------------------------------
% -- test cases
call(_Config) ->
    {ok,<<"abcdef">>} = tp_json_rpc:call(?HOST, "append", [<<"abc">>,<<"def">>]).

call_errors(_Config) ->
    {error, method_not_found} = tp_json_rpc:call(?HOST, "nonamemethod", [<<"test">>]),
    {error, invalid_params} = tp_json_rpc:call(?HOST, "append", [1]),
    {error, 30000} = tp_json_rpc:call(?HOST, "return_error", [30000]),
    {error, syntax_error} = tp_json_rpc:call("http://localhost:5671/", "foo", []).

call_http_error(_Config) ->
    {error, {http, _Reason}} = tp_json_rpc:call("http://localhost:44557", "foo", []).

notification(_Config) ->
    ok = tp_json_rpc:notification(?HOST, "echo", [<<"test">>]).

notification_http_error(_Config) ->
    {error, {http, _Reason}} = tp_json_rpc:notification("http://localhost:44557", "foo", []).

call_np(_Config) ->
    {ok, <<"cdab">>} = tp_json_rpc:call_np(?HOST, "append", [{str2, <<"ab">>}, {str1, <<"cd">>}]).

call_np_method_not_found(_Config) ->
    {error, method_not_found} = tp_json_rpc:call_np(?HOST, "nonamemethod", [{str2, <<"ab">>}, {str1, <<"cd">>}]).

call_np_http_error(_Config) ->
    {error, {http, _Reason}} = tp_json_rpc:call_np("http://localhost:44557", "foo", [{str2, <<"ab">>}, {str1, <<"cd">>}]).

% ---------------------------------------------------------------------
% -- common_test callbacks
all() ->
    [call, call_errors, call_http_error,
     notification, notification_http_error,
     call_np, call_np_method_not_found, call_np_http_error].

init_per_suite(Config) ->
	application:start(inets),
	application:start(tp_json_rpc),
    tpjrpc_example_service:register_yourself(),
    Config.

end_per_suite(_Config) ->
	application:stop(tp_json_rpc),
	application:stop(inets).