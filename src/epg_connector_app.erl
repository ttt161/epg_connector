%%%-------------------------------------------------------------------
%% @doc epg_connector public API
%% @end
%%%-------------------------------------------------------------------

-module(epg_connector_app).

-behaviour(application).

-export([start/2, stop/1]).

-export([start_pools/1]).
-export([unwrap_secret/1]).

-type db_ref() :: atom().
-type db_opts() :: #{
    host => string(),
    port => pos_integer(),
    database => string(),
    username => string(),
    password => string() | function()
}.
-type databases() :: #{db_ref() := db_opts()}.
-type pool_name() :: atom().
-type pool_opts() :: #{
    database := db_ref(),
    %% MaxConnections - PermanentConnections = EphemeralConnections
    size := pos_integer() | {PermanentConnections :: pos_integer(), MaxConnections :: pos_integer()}
}.
-type pools() :: #{pool_name() := pool_opts()}.
-type db_configs() :: #{
    databases := databases(),
    pools := pools()
}.

-export_type([databases/0]).
-export_type([pools/0]).
-export_type([db_configs/0]).
-export_type([db_opts/0]).
-export_type([db_ref/0]).

start(_StartType, _StartArgs) ->
    Databases0 = application:get_env(epg_connector, databases, #{}),
    _Databases = wrap_secrets(Databases0),
    epg_connector_sup:start_link().

stop(_State) ->
    ok.

-spec start_pools(db_configs()) -> supervisor:startchild_ret().
start_pools(#{databases := Databases, pools := Pools} = _DbConf) ->
    ChildSpec = epg_connector_sup:pool_specs(Pools, Databases),
    supervisor:start_child(epg_connector_sup, ChildSpec).

-spec unwrap_secret(db_opts()) -> db_opts().
unwrap_secret(#{password := WrappedPass} = DbOpts) when is_function(WrappedPass) ->
    DbOpts#{password => WrappedPass()};
unwrap_secret(DbOpts) ->
    DbOpts.

%% internal functions

-spec wrap_secret(db_opts()) -> db_opts().
wrap_secret(#{password := Pass} = DbOpts) when is_list(Pass) ->
    DbOpts#{password => fun() -> Pass end};
wrap_secret(DbOpts) ->
    DbOpts.

wrap_secrets(Databases) ->
    DbConfig = update_db_config(Databases),
    ok = application:set_env(epg_connector, databases, DbConfig),
    DbConfig.

update_db_config(Databases) ->
    maps:fold(
        fun(DbName, ConnOpts, Acc) ->
            Acc#{DbName => wrap_secret(ConnOpts)}
        end,
        #{},
        Databases
    ).
