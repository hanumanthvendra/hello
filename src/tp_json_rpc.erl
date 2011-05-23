% Copyright 2010-2011, Travelping GmbH <info@travelping.com>

% Permission is hereby granted, free of charge, to any person obtaining a
% copy of this software and associated documentation files (the "Software"),
% to deal in the Software without restriction, including without limitation
% the rights to use, copy, modify, merge, publish, distribute, sublicense,
% and/or sell copies of the Software, and to permit persons to whom the
% Software is furnished to do so, subject to the following conditions:

% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.

% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
% DEALINGS IN THE SOFTWARE.

% @doc This module contains a JSON-RPC client.
-module(tp_json_rpc).

-export([start/0, handle_request/2, call/3, notification/3, call_np/3]).

-include("jrpc_internal.hrl").
-define(TIME_OUT, {timeout, 15000}).

%% @type binary_or_string() = binary() | string()
%% @type rpc_error() = {error, {http, term()}} | {error, syntax_error}
%%                   | {error, invalid_request} | {error, method_not_found} | {error, invalid_params}
%%                   | {error, internal_error} | {error, internal_error} | {error, integer()}

%% @doc Starts the application. This is useful for debugging purposes.
start() ->
    application:start(inets),
    application:start(tp_json_rpc).

handle_request(Service, JSON) ->
    Resp = case tpjrpc_proto:request_json(JSON) of
               {ok, Request}  ->
                   tp_json_rpc_service:handle_request(Service, Request);
               {batch, Valid, Invalid} ->
                   Resps = tp_json_rpc_service:handle_request(Service, Valid),
                   Invalid ++ Resps;
               {error, Error} ->
                   Error
           end,
    ResponseJSON = tpjrpc_proto:response_json(Resp),
    tpjrpc_logger:log(JSON,ResponseJSON),
    ResponseJSON.

rpc_request(HostURL, #request{id = Id, method = Method, params = ArgList}) ->
    Methodto    = into_bin(Method),
    IDField     = case Id of
                      undefined -> [];
                      _         -> [{"id", Id}]
                  end,
    RequestJSON = tpjrpc_json:encode({IDField ++ [{"jsonrpc", <<"2.0">>}, {"version", <<"1.1">>}, {"method", Methodto}, {"params", ArgList}]}),
    {ok, Hostname, _Path} = split_url(HostURL),
    Headers     = [{"Host", Hostname}, {"Connection", "keep-alive"},
                   {"Content-Length", integer_to_list(iolist_size(RequestJSON))},
                   {"Content-Type", "application/json"},
                   {"Accept", "application/json"},
                   {"User-Agent", "tp_json_rpc"}],
    HTTPRequest = {HostURL, Headers, "application/json", RequestJSON},
    case httpc:request(post, HTTPRequest, [?TIME_OUT], [{headers_as_is, true}, {full_result, false}]) of
       {ok, {_Code, Body}} -> {ok, Body};
       {error, Reason}     -> {error, {http, Reason}}
    end.

%% @spec (Host::string(), Method::binary_or_string(), Arguments::list()) -> {ok, tpjrpc_json:json()} | {error, rpc_error()}
%% @doc Function performs a JSON-RPC method call using HTTP.
call(Host, Method, ArgList) when is_list(ArgList) or is_tuple(ArgList) ->
    Request = #request{id = 1, method = Method, params = ArgList},
    case rpc_request(Host, Request) of
        {error, Error} -> {error, Error};
        {ok, Body} ->
            case tpjrpc_json:decode(Body) of
               {error, syntax_error} -> {error, syntax_error};
               {ok, {Props}, _Rest} ->
                   case proplists:get_value("error", Props, null) of
                       null ->
                           Result = proplists:get_value("result", Props),
                           {ok, Result};
                       {ErrorObject} ->
                           case proplists:get_value("code", ErrorObject) of
                               -32600 -> {error, invalid_request};
                               -32601 -> {error, method_not_found};
                               -32602 -> {error, invalid_params};
                               -32603 -> {error, internal_error};
                               Code when (Code >= -32099) and (Code =< -32000) -> {error, server_error};
                               Code -> {error, Code}
                           end
                   end
            end
    end.

%% @spec (Host::string(), Method::binary_or_string(), Arguments::list()) -> ok | {error, rpc_error()}
%% @doc Special form of a JSON-RPC method call that returns no result.
notification(Host, Method, ArgList) ->
    case rpc_request(Host, #request{method=Method, params=ArgList}) of
        {error, Reason} -> {error, Reason};
        {ok, _Body}     -> ok
    end.

%% @spec (Host::string(), Method::binary_or_string(), Arguments::[{string(), tpjrpc_json:json()}]) -> {ok, tpjrpc_json:json()} | {error, rpc_error()}
%% @doc Performs a JSON-RPC method call with named parameters (property list).
call_np(Host, Method, List) when is_list(List) ->
    call(Host, Method, {List}).

into_bin(Bin) when is_list(Bin) -> list_to_binary(Bin);
into_bin(Bin)                   -> Bin.

split_url(URL) ->
    case re:run(URL, "^http://([^/]+)(.*)", [{capture, all_but_first, list}]) of
        {match, [Host, Path]} -> {ok, Host, Path};
        nomatch               -> {error, not_url}
    end.
