FROM erlang:27-alpine

WORKDIR /app

RUN apk add --no-cache make bash

COPY . .

RUN rebar3 as prod release

EXPOSE 8080

CMD ["_build/prod/rel/time_tracker/bin/time_tracker", "foreground"]
