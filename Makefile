.PHONY: deps compile test shell release run

deps:
	rebar3 get-deps

compile:
	rebar3 compile

test:
	rebar3 eunit

shell:
	rebar3 shell

release:
	rebar3 as prod release

run: release
	_build/prod/rel/time_tracker/bin/time_tracker foreground
