%
% Copyright (c) 2016-2018 Petr Gotthard <petr.gotthard@centrum.cz>
% All rights reserved.
% Distributed under the terms of the MIT License. See the LICENSE file.
%
-module(loramote_tests).
-include_lib("eunit/include/eunit.hrl").

-define(AREA, <<"testarea">>).
-define(NET, <<"testnet">>).
-define(GWMAC, <<16#0000000000000000:64>>).
-define(GROUP, <<"testgroup">>).
-define(PROF, <<"testprof">>).
-define(NODE0, {<<16#11223344:32>>, <<"2B7E151628AED2A6ABF7158809CF4F3C">>, <<"2B7E151628AED2A6ABF7158809CF4F3C">>}).
-define(NODE1, {<<16#22222222:32>>, <<"77CC3C53DC57CB932735E76F50570CAE">>, <<"172EB40016E87DE0701C00E4AA034085">>}).

-record(state, {gateway, node1}).

% fixture is my friend
loramote_test_() ->
    {setup,
        fun() ->
            {ok, _} = application:ensure_all_started(lorawan_server),
            lager:set_loglevel(lager_console_backend, debug),
            test_admin:add_area(?AREA),
            test_admin:add_gateway(?AREA, ?GWMAC),
            test_admin:add_network(?NET),
            {ok, Gateway} = test_forwarder:start_link(?GWMAC, {"localhost", 1680}),
            test_admin:add_group(?NET, ?GROUP),
            test_admin:add_profile(?GROUP, ?PROF),
            test_admin:add_node(?PROF, ?NODE0),
            test_admin:add_node(?PROF, ?NODE1),
            {ok, Node1} = test_mote:start_link(?NODE1, Gateway),
            #state{gateway=Gateway, node1=Node1}
        end,
        fun(#state{gateway=Gateway, node1=Node1}) ->
            test_forwarder:stop(Gateway),
            test_mote:stop(Node1),
            application:stop(lorawan_server),
            application:stop(mnesia)
        end,
        fun loramote_test/1}.

loramote_test(#state{gateway=Gateway, node1=Node1}) ->
    [
    ?_assertEqual({error, timeout}, test_forwarder:push_and_pull(Gateway, <<"bad_json">>)),
    % -- random messages from LoRa Mote
    ?_assertEqual({ok, <<"YEQzIhEAAQAChkQA7Q4=">>}, test_forwarder:push_and_pull(Gateway, test_forwarder:rxpk("QEQzIhEABAACP24OaiNddeeybMAun0EwVHf4eaY="))),
    ?_assertEqual({ok, <<"YEQzIhEBAgAGAnyjfkSq">>}, test_forwarder:push_and_pull(Gateway, test_forwarder:rxpk("QEQzIhEA0AACHaxbOsSlM9izylIPYNdD3QuCrXI="))),
    % -- sequence tests
    {inorder, [
        ?_assertEqual({ok, false, 2, <<1>>}, test_mote:push_and_pull(Node1, false, 1, 2, test_mote:semtech_payload(0))),
        ?_assertEqual({ok, false, 2, <<0>>}, test_mote:push_and_pull(Node1, false, 2, 2, test_mote:semtech_payload(1))),
        % old frame
        ?_assertEqual({error, timeout}, test_mote:push_and_pull(Node1, false, 1, 2, test_mote:semtech_payload(0))),
        % retransmission, the payload shall be ignored
        ?_assertEqual({ok, false, 2, <<0>>}, test_mote:push_and_pull(Node1, false, 2, 2, test_mote:semtech_payload(0))),
        % next normal frame, confirmed
        ?_assertEqual({ok, true, 2, <<1>>}, test_mote:push_and_pull(Node1, true, 3, 2, test_mote:semtech_payload(2))),
        % ignored non-confirmed
        ?_assertEqual({error, timeout}, test_mote:push_and_pull(Node1, false, 4, 2, <<>>)),
        % ignored confirmed
        ?_assertEqual({ok, true, undefined, <<>>}, test_mote:push_and_pull(Node1, true, 5, 2, <<>>))
        ]}
    ].

% end of file
