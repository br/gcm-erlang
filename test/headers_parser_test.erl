-module(headers_parser_test).
-compile([export_all]).

-include_lib("eunit/include/eunit.hrl").

get_retry_after_when_set_test() ->
    application:start(qdate),
    TargetDate = qdate:add_seconds(120, qdate:unixtime()),
    TargetTime = qdate:to_string("Y-m-d h:ia",TargetDate),
    Headers = [{"retry-after", TargetTime}],
    ?assertMatch({ok,I} when is_integer(I), headers_parser:retry_after_from(Headers)).
 
get_retry_after_when_set_as_string_test() ->
    Headers = [{"retry-after", "120"}],
    ?assertEqual({ok,120}, headers_parser:retry_after_from(Headers)).
 
get_retry_after_when_not_set_test() ->
    Headers = [],
    ?assertEqual(no_retry, headers_parser:retry_after_from(Headers)),.
    