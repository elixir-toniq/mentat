defmodule Mentat do
  @external_resource readme = "README.md"
  @moduledoc readme
             |> File.read!()
             |> String.split("<!--MDOC !-->")
             |> Enum.fetch!(1)

  use Supervisor
  use Oath

  @type cache_opts() :: Keyword.t()
  @type name :: atom()
  @type key :: term()
  @type value :: term()
  @type put_opts :: [
    {:ttl, pos_integer() | :infinity},
  ]

  @default_limit %{reclaim: 0.1}

  alias Mentat.Janitor

  defp cache_opts do
    import Norm

    coll_of(
      one_of([
        {:name, spec(is_atom)},
        {:cleanup_interval, spec(is_integer and & &1 > 0)},
        {:ets_args, spec(is_list)},
        {:ttl, one_of([spec(is_integer and & &1 > 0), :infinity])},
        {:clock, spec(is_atom)},
        {:limit, coll_of(one_of([
          {:size, spec(is_integer and & &1 > 0)},
          {:reclaim, spec(is_float)},
        ]))}
      ])
    )
  end

  @doc false
  def child_spec(opts) do
    name = opts[:name] || raise ArgumentError, ":name is required"

    %{
      id: name,
      type: :supervisor,
      start: {__MODULE__, :start_link, [opts]},
    }
  end

  @doc """
  Starts a new cache.

  Options:
  * `:name` - the cache name as an atom. required.
  * `:cleanup_interval` - How often the janitor process will remove old keys. Defaults to 5_000.
  * `:ets_args` - Additional arguments to pass to `:ets.new/2`.
  * `:ttl` - The default ttl for all keys. Default `:infinity`.
  * `:limit` - Limits to the number of keys a cache will store. Defaults to `:none`.
    * `:size` - The maximum number of values to store in the cache.
    * `:reclaim` - The percentage of keys to reclaim if the limit is exceeded. Defaults to 0.1.
  """
  @spec start_link(cache_opts()) :: Supervisor.on_start()
  def start_link(args) do
    args = Norm.conform!(args, cache_opts())
    name = args[:name]
    Supervisor.start_link(__MODULE__, args, name: name)
  end

  @doc """
  Fetches a value or executes the fallback function. The function can return
  either `{:commit, term()}` or `{:ignore, term()}`. If `{:commit, term()}` is
  returned, the value will be stored in the cache before its returned. See the
  "TTLs" section for a list of options.

  Since `fetch` is logically the same as a `get` (and also a `put` if
  `{:commit, term()}` is returned from the fallback function), it shares the
  same Telemetry events (`[:mentat, :get]` and `[:mentat, :put]`).

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
  @spec fetch(name(), key(), put_opts(), (key() -> {:commit, value()} | {:ignore, value()})) :: value()
  def fetch(cache, key, opts \\ [], fallback) do
    {status, value} = lookup(cache, key)
    :telemetry.execute([:mentat, :get], %{status: status}, %{key: key, cache: cache})

    if status == :hit do
      value
    else
      case fallback.(key) do
        {:commit, value} -> put(cache, key, value, opts)
        {:ignore, value} -> value
      end
    end
  end

  @doc """
  Retrieves a value from a the cache. Returns `nil` if the key is not found.
  """
  @spec get(name(), key()) :: value()
  def get(cache, key) do
    {status, value} = lookup(cache, key)
    :telemetry.execute([:mentat, :get], %{status: status}, %{key: key, cache: cache})
    value
  end


  @doc """
  Puts a new key into the cache. See the "TTLs" section for a list of
  options.
  """
  @spec put(name(), key(), value(), put_opts()) :: value() | no_return()
  @decorate pre("ttls are positive", fn _, _, _, opts ->
    if opts[:ttl], do: opts[:ttl] > 0, else: true
  end)
  @decorate post("value is returned", fn _, _, value, _, return ->
    value == return
  end)
  def put(cache, key, value, opts \\ [])
  def put(cache, key, value, opts) do
    config = get_config(cache)
    :telemetry.execute([:mentat, :put], %{}, %{key: key, cache: cache})

    now = ms_time(config.clock)
    ttl = opts[:ttl] || config.ttl

    if ttl < 0 do
      raise ArgumentError, "`:ttl` must be greater than 0"
    end

    true = :ets.insert(cache, {key, value, now, ttl})

    # If we've reached the limit on the table, we need to purge a number of old
    # keys. We do this by calling the janitor process and telling it to purge.
    # This will, in turn call immediately back into the remove_oldest function.
    # The back and forth here is confusing to follow, but its necessary because
    # we want to do the purging in a different process.
    if config.limit != :none && :ets.info(cache, :size) > config.limit.size do
      count = ceil(config.limit.size * config.limit.reclaim)
      Janitor.reclaim(janitor(cache), count)
    end

    value
  end

  @doc """
  Updates a keys inserted at time. This is useful in conjunction with limits
  when you want to evict the oldest keys. Returns `true` if the key was found
  and `false` if it was not.
  """
  @spec touch(name(), key()) :: boolean()
  def touch(cache, key) do
    config = get_config(cache)
    now    = ms_time(config.clock)
    :ets.update_element(cache, key, {3, now})
  end

  @doc """
  Deletes a key from the cache
  """
  @spec delete(name(), key()) :: true
  def delete(cache, key) do
    :ets.delete(cache, key)
  end

  @doc """
  Returns a list of all keys. By default this function only returns keys
  that have no exceeded their TTL. You can pass the `all: true` option to the function
  in order to return all present keys, which may include keys that have exceeded
  their TTL but have not been purged yet.
  """
  @spec keys(name()) :: [key()]
  def keys(cache, opts \\ []) do
    ms = if opts[:all] == true do
      [{{:"$1", :_, :_, :_}, [], [:"$1"]}]
    else
      config = get_config(cache)
      now    = ms_time(config.clock)
      [
        {{:"$1", :_, :"$2", :"$3"},
         [
           {:orelse,
            {:andalso, {:is_integer, :"$3"}, {:>, {:+, :"$2", :"$3"}, now}},
            {:==, :"$3", :infinity}}
         ], [:"$1"]}
      ]
    end

    :ets.select(cache, ms)
  end

  @doc """
  Removes all keys from the cache.
  """
  @spec purge(name()) :: true
  def purge(cache) do
    :ets.delete_all_objects(cache)
  end

  @doc false
  def remove_expired(cache) do
    config = get_config(cache)
    now    = ms_time(config.clock)

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
    name     = args[:name]
    interval = args[:cleanup_interval] || 5_000
    limit    = args[:limit] || :none
    limit    = if limit != :none, do: Map.merge(@default_limit, Map.new(limit)), else: limit
    ets_args = args[:ets_args] || []
    clock    = args[:clock] || System
    ttl      = args[:ttl] || :infinity
    ^name    = :ets.new(name, [:set, :named_table, :public] ++ ets_args)

    put_config(name, %{limit: limit, ttl: ttl, clock: clock})

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

  def stop(name) do
    Supervisor.stop(name)
  end

  defp lookup(cache, key) do
    config = get_config(cache)
    now    = ms_time(config.clock)

    case :ets.lookup(cache, key) do
      [] -> {:miss, nil}
      [{^key, _val, ts, ttl}] when is_integer(ttl) and ts + ttl <= now -> {:miss, nil}
      [{^key, val, _ts, _expire_at}] -> {:hit, val}
    end
  end

  defp put_config(cache, config) do
    :persistent_term.put({__MODULE__, cache}, config)
  end

  defp get_config(cache) do
    :persistent_term.get({__MODULE__, cache})
  end

  defp ms_time(clock) do
    # Clock is going `System` in most cases and is set inside the init function
    clock.monotonic_time(:millisecond)
  end

  defp janitor(name) do
    :"#{name}_janitor"
  end
end
