# Mentat

<!--MDOC !-->

[![Elixir CI](https://github.com/keathley/mentat/workflows/Elixir%20CI/badge.svg)](https://github.com/keathley/mentat/actions)
[![Module Version](https://img.shields.io/hexpm/v/mentat.svg)](https://hex.pm/packages/mentat)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/mentat/)
[![Total Download](https://img.shields.io/hexpm/dt/mentat.svg)](https://hex.pm/packages/mentat)
[![License](https://img.shields.io/hexpm/l/mentat.svg)](https://github.com/keathley/mentat/blob/main/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/keathley/mentat.svg)](https://github.com/keathley/mentat/commits/main)

Provides a super simple cache with ttls.

## Usage

A cache must be given a name when its started.

```elixir
Mentat.start_link(name: :my_cache)
```

After its been started you can store and retrieve values:

```elixir
Mentat.put(:my_cache, user_id, user)
user = Mentat.get(:my_cache, user_id)
```

## TTLs

Both `put` and `fetch` operations allow you to specify the key's TTL. If no
TTL is provided then the TTL is set to `:infinity`. TTL times are always
in milliseconds.

```elixir
Mentat.put(:my_cache, :key, "value", [ttl: 5_000])

Mentat.fetch(:my_cache, :key, [ttl: 5_000], fn key ->
  {:commit, "value"}
end)
```

### Default TTLs

You can set a global TTL for all new keys

## Limits

Mentat supports optional limits per cache.

```elixir
Mentat.start_link(name: LimitedCache, limit: [size: 100])
```

When the limit is reached, the janitor will asynchronously reclaim a percentage of the keys. The janitor will removed the oldest entries first. If multiple entries share a timestamp (they were inserted at the same time) than they are removed by key in ascending order.

## Telemetry

Mentat publishes multiple telemetry events.

  * `[:mentat, :get, :start]` - executed before retrieving a value from cache
    Measurements are:

    * `:system_time` - Current system time
    * `:monotonic_time` - Current monotonic time

    Metadata are:

      * `:key` - The key requested
      * `:cache` - The cache name

  * `[:mentat, :get, :stop]` - executed before retrieving a value from cache
    Measurements are:

    * `:duration` - Duration in native units
    * `:monotonic_time` - Current monotonic time

    Metadata are:

      * `:key` - The key requested
      * `:cache` - The cache name
      * `:status` - Can be either `:hit` or `:miss` depending on if the key was found in the cache

  * `[:mentat, :put, :start]` - executed before putting a key into the cache.
    Measurements are:

    * `:system_time` - Current system time
    * `:monotonic_time` - Current monotonic time

    Metadata are:

      * `:key` - The key requested
      * `:cache` - The name of the cache

  * `[:mentat, :put, :stop]` - executed after putting a key into the cache.
    Measurements are:

    * `:duration` - Current system time
    * `:monotonic_time` - Current monotonic time

    Metadata are:

      * `:key` - The key requested
      * `:cache` - The name of the cache

  * `[:mentat, :janitor, :cleanup]` - executed after old keys are cleaned
    from the cache. Measurements are:

    * `:duration` - the time it took to clean up the old keys. Time is
      in `:native` units.
    * `total_removed_keys` - The count of keys removed from the cache.

    Metadata are:

      * `cache` - The cache name.

## Contracts

Mentat supports `Oath` contracts. This helps ensure that you're using Mentat correctly
and that Mentat is returning what you expect. You can enable contracts by setting

```elixir
config :oath,
  enable_contracts: true
```

And then recompiling Mentat in dev and test environments:

```
MIX_ENV=dev mix deps.compile mentat --force
MIX_ENV=test mix deps.compile mentat --force
```

## Installation

```elixir
def deps do
  [
    {:mentat, "~> 0.7"}
  ]
end
```

## Should I use this?

There are (many) other caching libraries out there that provide many more features
than Mentat. But, it turns out, I don't need most of those features. Mentat is
intended to be very small while still providing the necessary components. The
test suite is sparse, but we've been using this implementation in production
for a while now so I feel pretty confident in it.
