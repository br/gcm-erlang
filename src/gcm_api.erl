-module(gcm_api).
-export([push/3]).

-define(BASEURL, "https://gcm-http.googleapis.com/gcm/send").

-type header()  :: {string(), string()}.
-type headers() :: [header(),...].
-type regids()  :: [binary(),...].
-type message() :: [tuple(),...].
-type result()  :: {number(), non_neg_integer(), non_neg_integer(), non_neg_integer(), [any()]}.

-spec push(regids(),message(),string()) -> {'error',any()} | {'noreply','unknown'} | {'ok',result()}.
push(RegIds, Message, Key) ->
    Request = jsx:encode([{<<"registration_ids">>, RegIds}|Message]),
    ApiKey = string:concat("key=", Key),
    StartTime = now(),
    try httpc:request(post, {?BASEURL, [{"Authorization", ApiKey}], "application/json", Request}, [], []) of
        {ok, {{_, 200, _}, _Headers, Body}} ->
            EndTime = now(),
            ExecTime = timer:now_diff(EndTime, StartTime)/1000,
            Json = jsx:decode(response_to_binary(Body)),
            ok = exometer:update([ndc, alert, gcm_request_time], ExecTime),
            case  ExecTime > 5000 of 
             true ->    
                  FirstResult = lists:nth(1, proplists:get_value(<<"results">>, Json)),
                  MessageId = proplists:get_value(<<"message_id">>, FirstResult),
                  error_logger:warning_msg("The request with message_id ~p took ~p milliseconds", [MessageId, ExecTime]),
                  error_logger:warning_msg("Result was: ~p~n", [Json]);
              false -> 
                    ok
            end,
            {ok, result_from(Json)};
        {ok, {{_, 400, _}, _, Body}} ->
            error_logger:error_msg("Error in request. Reason was: Bad Request - ~p~n", [Body]),
            {error, Body};
        {ok, {{_, 401, _}, _, _}} ->
            error_logger:error_msg("Error in request. Reason was: authorization error~n", []),
            {error, auth_error};
        {ok, {{_, Code, _}, Headers, _}} when Code >= 500 andalso Code =< 599 ->
            RetryTime = retry_after_from(Headers),
            error_logger:error_msg("Error in request. Reason was: retry. Will retry in: ~p~n", [RetryTime]),
            {error, {retry, RetryTime}};
        {ok, {{_StatusLine, _, _}, _, _Body}} ->
            error_logger:error_msg("Error in request. Reason was: timeout~n", []),
            {error, timeout};
        {error, Reason} ->
            error_logger:error_msg("Error in request. Reason was: ~p~n", [Reason]),
            {error, Reason};
        OtherError ->
            error_logger:error_msg("Error in request. Reason was: ~p~n", [OtherError]),
            {noreply, unknown}
    catch
        Exception ->
            error_logger:error_msg("Error in request. Exception ~p while calling URL: ~p~n", [Exception, ?BASEURL]),
            {error, Exception}
    end.

-spec response_to_binary(binary() | list()) -> binary().
response_to_binary(Json) when is_binary(Json) ->
    Json;

response_to_binary(Json) when is_list(Json) ->
    list_to_binary(Json).

-spec result_from([{binary(),any()}]) -> result().
result_from(Json) ->
    {
      proplists:get_value(<<"multicast_id">>, Json),
      proplists:get_value(<<"success">>, Json),
      proplists:get_value(<<"failure">>, Json),
      proplists:get_value(<<"canonical_ids">>, Json),
      proplists:get_value(<<"results">>, Json)
    }.

-spec retry_after_from(headers()) -> 'no_retry' | non_neg_integer().
retry_after_from(Headers) ->
    case proplists:get_value("retry-after", Headers) of
        undefined ->
            no_retry;
        RetryTime ->
            case string:to_integer(RetryTime) of
                {Time, _} when is_integer(Time) ->
                    Time;
                {error, no_integer} ->
                    Date = qdate:to_unixtime(RetryTime),
                    Date - qdate:unixtime()
            end
    end.
