# Mentat

Provides a super simple cache with ttls.

[Docs](https://hexdocs.pm/mentat).

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

## Installation

```elixir
def deps do
  [
    {:mentat, "~> 0.1"}
  ]
end
```

## Should I use this?

There are (many) other caching libraries out there that provide many more features
than Mentat. But, it turns out, I don't need most of those features. Mentat is
intended to be very small while still providing the necessary components. The
test suite is sparse, but we've been using this implementation in production
for a while now so I feel pretty confident in it.
