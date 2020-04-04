defmodule Mentat do
  @moduledoc """
  Provides a basic cache with ttls.

  ## Usage

  A cache must be given a name when its started.

  ```
  Mentat.start_link(name: :my_cache)
  ```

  After its been started you can store and retrieve values:

  ```
  Mentat.put(:my_cache, user_id, user)
  user = Mentat.get(:my_cache, user_id)
  ```

  ## TTLs

  Both `put` and `fetch` operations allow you to specify the key's TTL. If no
  TTL is provided then the TTL is set to `:infinity`. TTL times are always
  in milliseconds.

  ```
  Mentat.put(:my_cache, :key, "value", [ttl: 5_000])

  Mentat.fetch(:my_cache, :key, [ttl: 5_000], fn key ->
    {:commit, "value"}
  end)
  ```

  ## Telemetry

  Mentat publishes multiple telemetry events.

    * `[:mentat, :get]` - executed after retrieving a value from the cache.
      Measurements are:

      * `:status` - Can be either `:hit` or `:miss` depending on if the key was
        found in the cache.

    Metadata are:

      * `:key` - The key requested
      * `:cache` - The cache name

  * `[:mentat, :put]` - executed when putting a key into the cache. No
    measurements are provided. Metadata are:

    * `:key` - The key requested
    * `:cache` - The name of the cache

  * `[:mentat, :janitor, :cleanup]` - executed after old keys are cleaned
    from the cache. Measurements are:

    * `:duration` - the time it took to clean up the old keys. Time is
      in `:native` units.
    * `total_removed_keys` - The count of keys removed from the cache.

    Metadata are:
    * `cache` - The cache name.
  """
  use Supervisor

  @doc """
  Starts a new cache.

  Options:

  `:name` - The name of the cache
  `:cleanup_interval` - How often the janitor process will remove old keys (defaults to 5_000).
  """
  def start_link(args) do
    name = Keyword.get(args, :name) || raise ArgumentError, "must supply a name for the cache"
    Supervisor.start_link(__MODULE__, args, name: name)
  end

  @doc """
  Retrieves a value from a the cache. Returns `nil` if the key is not found.
  """
  def get(cache, key, opts \\ []) do
    now = ms_time(opts)

    case :ets.lookup(cache, key) do
      [] ->
        :telemetry.execute([:mentat, :get], %{status: :miss}, %{key: key, cache: cache})
        nil

      [{^key, _val, expire_at}] when expire_at <= now ->
        :telemetry.execute([:mentat, :get], %{status: :miss}, %{key: key, cache: cache})
        nil

      [{^key, val, _expire_at}] ->
        :telemetry.execute([:mentat, :get], %{status: :hit}, %{key: key, cache: cache})
        val
    end
  end

  @doc """
  Fetches a value or executes the fallback function. The function can return
  either `{:commit, term()}` or `{:ignore, term()}`. If `{:commit, term()}` is
  returned, the value will be stored in the cache before its returned. See the
  "TTLs" section for a list of options.

  ## Example

  ```
  Mentat.fetch(:cache, user_id, fn user_id ->
    case get_user(user_id) do
      {:ok, user} ->
        {:commit, user}

      error ->
        {:ignore, error}
    end
  end)
  ```
  """
  def fetch(cache, key, opts \\ [], fallback) do
    with nil <- get(cache, key, opts) do
      case fallback.(key) do
        {:commit, value} ->
          put(cache, key, value, opts)
          value

        {:ignore, value} ->
          value
      end
    end
  end

  @doc """
  Puts a new key into the cache. See the "TTLs" section for a list of
  options.
  """
  def put(cache, key, value, opts \\ []) do
    :telemetry.execute([:mentat, :put], %{}, %{key: key, cache: cache})

    case Keyword.get(opts, :ttl) do
      nil ->
        :ets.insert(cache, {key, value, :infinity})

      millis ->
        expire_at = ms_time(opts) + millis
        :ets.insert(cache, {key, value, expire_at})
    end
  end

  @doc """
  Returns a list of all keys.
  """
  def keys(cache) do
    # :ets.fun2ms(fn({key, _, _} -> key end))
    ms = [{{:"$1", :_, :_}, [], [:"$1"]}]
    :ets.select(cache, ms)
  end

  @doc """
  Removes all keys from the cache.
  """
  def purge(cache) do
    :ets.delete_all_objects(cache)
  end

  @doc false
  def remove_expired(cache, opts \\ []) do
    now = ms_time(opts)

    # Match spec is found by calling:
    # :ets.fun2ms(fn {_key, _value, expire_at} when expire_at <= now -> true end)
    ms = [{{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [true]}]

    :ets.select_delete(cache, ms)
  end

  def init(args) do
    name     = Keyword.get(args, :name)
    interval = Keyword.get(args, :cleanup_interval, 5_000)
    ^name    = :ets.new(name, [:set, :named_table, :public])

    children = [
      {Mentat.Janitor, [name: :"#{name}_janitor", interval: interval, cache: name]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp timer(opts) do
    Keyword.get(opts, :clock, System)
  end

  defp ms_time(opts) do
    timer(opts).monotonic_time(:millisecond)
  end
end

