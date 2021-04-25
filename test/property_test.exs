defmodule Mentat.PropertyTest do
  use ExUnit.Case, async: true
  use PropCheck
  use PropCheck.StateM

  alias Mentat.FakeTime

  defmodule Cache do
    alias Mentat.FakeTime

    def start_link do
      FakeTime.reset()
      Mentat.start_link(name: __MODULE__, clock: FakeTime)
    end

    def stop do
      Mentat.stop(__MODULE__)
    end

    def advance_time do
      FakeTime.incr()
    end

    def put(key, value) do
      Mentat.put(__MODULE__, key, value)
    end

    def put_ttl(key, value) do
      Mentat.put(__MODULE__, key, value, ttl: 1)
    end

    def get_known(key) do
      Mentat.get(__MODULE__, key)
    end

    def get_unknown(key) do
      Mentat.get(__MODULE__, key)
    end

    def delete(key) do
      Mentat.delete(__MODULE__, key)
    end

    def keys do
      Mentat.keys(__MODULE__)
    end

    def touch(key) do
      Mentat.touch(__MODULE__, key)
    end
  end

  property "cache respects ttls" do
    forall cmds <- commands(__MODULE__, initial_state()) do
      trap_exit do
        Cache.start_link()
        result = run_commands(__MODULE__, cmds)
        {history, state, result} = result
        Cache.stop()

        (result == :ok)
        |> when_fail(
          IO.puts """
          History: #{inspect history, pretty: true}
          State: #{inspect state, pretty: true}
          Result: #{inspect result, pretty: true}
          """
        )
      end
    end
  end

  def key, do: term()

  def value, do: term()

  def known_key(state) do
    keys = Enum.map(state.keys, & elem(&1, 0))
    elements(keys)
  end

  def unknown_key(state) do
    keys = Enum.map(state.keys, & elem(&1, 0))
    let k <- key() do
      # If we've seen this key before (which is unlikely but can happen),
      # we should try the generation again.
      if k in keys do
        unknown_key(state)
      else
        k
      end
    end
  end

  def initial_state, do: %{time: 0, keys: []}

  def command(%{keys: []}) do
    oneof([
      {:call, Cache, :put, [key(), value()]},
      {:call, Cache, :get_unknown, [key()]},
      {:call, Cache, :delete, [key()]},
      {:call, Cache, :touch, [key()]},
    ])
  end

  def command(state) do
    oneof([
      {:call, Cache, :put, [key(), value()]},
      {:call, Cache, :put_ttl, [key(), value()]},
      {:call, Cache, :advance_time, []},
      {:call, Cache, :get_known, [known_key(state)]},
      {:call, Cache, :get_unknown, [unknown_key(state)]},
      {:call, Cache, :delete, [known_key(state)]},
      {:call, Cache, :delete, [unknown_key(state)]},
      {:call, Cache, :touch, [known_key(state)]},
      {:call, Cache, :touch, [unknown_key(state)]},
      {:call, Cache, :keys, []},
    ])
  end

  # Next States

  def next_state(state, _, {:call, Cache, :put, [key, value]}) do
    keys = Enum.reject(state.keys, & elem(&1, 0) == key)
    keys = [{key, value, :infinity} | keys]
    %{state | keys: keys}
  end

  def next_state(state, _, {:call, Cache, :put_ttl, [key, value]}) do
    keys = Enum.reject(state.keys, & elem(&1, 0) == key)
    keys = [{key, value, state.time + 1} | keys]
    %{state | keys: keys}
  end

  def next_state(state, _, {:call, Cache, :delete, [key]}) do
    keys = Enum.reject(state.keys, fn {k, _, _} -> k == key end)
    %{state | keys: keys}
  end

  def next_state(state, _, {:call, Cache, :advance_time, _}) do
    %{state | time: state.time+1}
  end

  def next_state(state, _, {:call, Cache, :touch, [key]}) do
    keys = for {k, v, ttl} <- state.keys do
      if k == key && ttl != :infinity do
        # TTLs in our model are always +1 so we just bump the ttl again
        {k, v, state.time+1}
      else
        {k, v, ttl}
      end
    end

    %{state | keys: keys}
  end

  def next_state(state, _, {:call, Cache, _, _}) do
    state
  end

  # Preconditions

  def precondition(_, {:call, Cache, :put, _}) do
    true
  end

  def precondition(_, {:call, Cache, :put_ttl, _}) do
    true
  end

  def precondition(state, {:call, Cache, :get_known, [key]}) do
    keys = Enum.map(state.keys, & elem(&1, 0))
    key in keys
  end

  def precondition(_, {:call, Cache, :get_unknown, _}) do
    true
  end

  def precondition(_, {:call, Cache, :delete, _}) do
    true
  end

  def precondition(_, {:call, Cache, :keys, _}) do
    true
  end

  def precondition(_, {:call, Cache, :touch, _}) do
    true
  end

  def precondition(_, {:call, Cache, :advance_time, _}) do
    true
  end

  # Post conditions

  def postcondition(_, {:call, Cache, :put, [_key, value]}, result) do
    result == value
  end

  def postcondition(_, {:call, Cache, :put_ttl, [_key, value]}, result) do
    result == value
  end

  def postcondition(state, {:call, Cache, :get_known, [key]}, result) do
    {_, value, ttl} = Enum.find(state.keys, fn {k, _, _} -> k == key end)

    if ttl <= state.time do
      result == nil
    else
      result != nil && value == result
    end
  end

  def postcondition(_, {:call, Cache, :get_unknown, [_]}, result) do
    result == nil
  end

  def postcondition(_, {:call, Cache, :delete, [_]}, result) do
    result == true
  end

  def postcondition(state, {:call, Cache, :keys, _}, result) do
    keys =
      state.keys
      |> Enum.filter(fn {_, _, ttl} -> ttl > state.time end)
      |> Enum.map(& elem(&1, 0))

    Enum.sort(keys) == Enum.sort(result)
  end

  def postcondition(state, {:call, Cache, :touch, [key]}, result) do
    keys = Enum.map(state.keys, & elem(&1, 0))
    result == (key in keys)
  end

  def postcondition(_state, {:call, Cache, :advance_time, _}, result) do
    result
  end
end
