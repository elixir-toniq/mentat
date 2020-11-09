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

  ## Limits

  Mentat supports optional limits per cache.

  ```elixir
  Mentat.start_link(name: LimitedCache, limit: [size: 100])
  ```

  When the limit is reached, the janitor will asynchronously reclaim a percentage of the keys

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

  alias Mentat.Janitor

  @cache_options [
    name: [
      type: :atom,
      required: true,
    ],
    cleanup_interval: [
      type: :pos_integer,
      default: 5_000,
      doc: "How often the janitor process will remove old keys."
    ],
    ets_args: [
      type: :any,
      doc: "Additional arguments to pass to `:ets.new/2`.",
      default: [],
    ],
    limit: [
      doc: "Limits to the number of keys a cache will store.",
      type: :keyword_list,
      required: false,
      default: []
    ],
    ttl: [
      doc: "Default ttl in milliseconds to use for all keys",
      type: :any,
      required: false,
      default: :infinity
    ]
  ]

  @limit_opts [
    size: [
      type: :pos_integer,
      doc: "The maximum number of values to store in the cache.",
      required: true
    ],
    reclaim: [
      type: :any,
      doc: "The percentage of keys to reclaim if the limit is exceeded.",
      default: 0.1
    ]
  ]

  @doc """
  Starts a new cache.

  Options:

  #{NimbleOptions.docs(@cache_options)}
  """
  def start_link(args) do
    args = NimbleOptions.validate!(args, @cache_options)
    name = args[:name]
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

      [{^key, _val, ts, ttl}] when is_integer(ttl) and ts + ttl <= now ->
        :telemetry.execute([:mentat, :get], %{status: :miss}, %{key: key, cache: cache})
        nil

      [{^key, val, _ts, _expire_at}] ->
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
    %{limit: limit, ttl: default_ttl} = :persistent_term.get({__MODULE__, cache})
    :telemetry.execute([:mentat, :put], %{}, %{key: key, cache: cache})

    now = ms_time(opts)
    ttl = Keyword.get(opts, :ttl) || default_ttl

    result = :ets.insert(cache, {key, value, now, ttl})

    # If we've reached the limit on the table, we need to purge a number of old
    # keys. We do this by calling the janitor process and telling it to purge.
    # This will, in turn call immediately back into the remove_oldest function.
    # The back and forth here is confusing to follow, but its necessary because
    # we want to do the purging in a different process.
    if limit != :none && :ets.info(cache, :size) > limit.size do
      count = ceil(limit.size * limit.reclaim)
      Janitor.reclaim(janitor(cache), count)
    end

    result
  end

  @doc """
  Updates a keys inserted at time. This is useful in conjunction with limits
  when you want to evict the oldest keys.
  """
  def touch(cache, key, opts \\ []) do
    :ets.update_element(cache, key, {3, ms_time(opts)})
  end

  @doc """
  Deletes a key from the cache
  """
  def delete(cache, key) do
    :ets.delete(cache, key)
  end

  @doc """
  Returns a list of all keys.
  """
  def keys(cache) do
    # :ets.fun2ms(fn({key, _, _} -> key end))
    ms = [{{:"$1", :_, :_, :_}, [], [:"$1"]}]
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

    # Find all expired keys by selecting the timestamp and ttl, adding them together
    # and finding the keys that are lower than the current time
    ms = [
      {{:_, :_, :"$1", :"$2"},
        [{:andalso, {:is_integer, :"$2"}, {:<, {:+, :"$1", :"$2"}, now}}], [true]}
    ]

    :ets.select_delete(cache, ms)
  end

  @doc false
  def remove_oldest(cache, count) do
    ms = [{{:_, :_, :"$1", :_}, [], [:"$1"]}]
    entries = :ets.select(cache, ms)

    oldest =
      entries
      |> Enum.sort()
      |> Enum.take(count)
      |> List.last()

    delete_ms = [{{:_, :_, :"$1", :_}, [{:"=<", :"$1", oldest}], [true]}]

    :ets.select_delete(cache, delete_ms)
  end

  def init(args) do
    name     = Keyword.get(args, :name)
    interval = Keyword.get(args, :cleanup_interval)
    limit    = Keyword.get(args, :limit)
    limit    = if limit == [], do: :none, else: Map.new(NimbleOptions.validate!(limit, @limit_opts))
    ets_args = Keyword.get(args, :ets_args)
    ttl      = Keyword.get(args, :ttl) || :infinity

    ^name    = :ets.new(name, [:set, :named_table, :public] ++ ets_args)

    :persistent_term.put({__MODULE__, name}, %{limit: limit, ttl: ttl})

    janitor_opts = [
      name: janitor(name),
      interval: interval,
      cache: name
    ]

    children = [
      {Mentat.Janitor, janitor_opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp timer(opts) do
    Keyword.get(opts, :clock, System)
  end

  defp ms_time(opts) do
    timer(opts).monotonic_time(:millisecond)
  end

  defp janitor(name) do
    :"#{name}_janitor"
  end
end
