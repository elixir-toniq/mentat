defmodule Mentat.PropertyTest do
  use ExUnit.Case, async: false
  use PropCheck, default_opts: [
    :verbose,
    {:numtests, 200},
    {:search_steps, 333},
  ]
  use PropCheck.StateM

  alias Mentat.FakeTime

  @cache TestCache
  @default_ttl 1

  property "cache respects ttls" do
    forall cmds <- commands(__MODULE__, initial_state()) do
      trap_exit do
        FakeTime.reset()
        Mentat.start_link(name: @cache, ttl: @default_ttl, clock: FakeTime)
        {history, state, result} = run_commands(__MODULE__, cmds)
        Mentat.stop(@cache)

        (result == :ok)
        |> when_fail(print_report({history, state, result}, cmds))
      end
    end
  end

  def initial_state, do: %{time: 0, keys: %{}}

  def known_key(state) do
    keys = Enum.map(state.keys, & elem(&1, 0))
    elements(keys)
  end

  def command(state) do
    key = if Enum.any?(state.keys) do
      oneof([known_key(state), term()])
    else
      term()
    end

    oneof([
      {:call, FakeTime, :advance_time, []},
      {:call, Mentat, :put, [@cache, key, term(), []]},
      {:call, Mentat, :put, [@cache, key, term(), [ttl: pos_integer()]]},
      {:call, Mentat, :put, [@cache, key, term(), [ttl: :infinity]]},
      {:call, Mentat, :get, [@cache, key]},
      {:call, Mentat, :delete, [@cache, key]},
      {:call, Mentat, :touch, [@cache, key]},
      {:call, Mentat, :keys, [@cache]},
    ])
  end

  # Next States

  def next_state(state, _, {:call, FakeTime, :advance_time, _}) do
    %{state | time: state.time+1}
  end

  def next_state(state, _, {:call, Mentat, :put, [_c, key, value, opts]}) do
    ttl = opts[:ttl] || @default_ttl
    put_in(state, [:keys, key], %{value: value, time: state.time, ttl: ttl})
  end

  def next_state(state, _, {:call, Mentat, :delete, [_c, key]}) do
    {_, keys} = pop_in(state.keys, [key])
    %{state | keys: keys}
  end

  def next_state(state, _, {:call, Mentat, :touch, [_c, key]}) do
    # If the key has been set we update its creation time. Otherwise
    # we leave the state alone
    if state.keys[key] do
      put_in(state, [:keys, key, :time], state.time)
    else
      state
    end
  end

  # No other commands update the state
  def next_state(state, _, {:call, Mentat, _, _}) do
    state
  end

  # Preconditions

  # There are no preconditions for our commands
  def precondition(_, _), do: true

  # Post conditions

  def postcondition(_, {:call, Mentat, :put, [_c, _k, value, _]}, result) do
    result == value
  end

  def postcondition(state, {:call, Mentat, :get, [_c, key]}, result) do
    data = state.keys[key]

    cond do
      data == nil ->
        result == nil

      data.ttl == :infinity ->
        data.value == result

      data.time + data.ttl <= state.time ->
        result == nil

      true ->
        data.value == result
    end
  end

  def postcondition(_, {:call, Mentat, :delete, [_c, _k]}, result) do
    result == true
  end

  def postcondition(state, {:call, Mentat, :keys, [_c]}, result) do
    keys =
      state.keys
      |> Enum.filter(fn {_, v} -> v.ttl == :infinity || v.time + v.ttl > state.time end)
      |> Enum.map(& elem(&1, 0))

    Enum.sort(keys) == Enum.sort(result)
  end

  def postcondition(state, {:call, Mentat, :touch, [_c, key]}, result) do
    keys = Enum.map(state.keys, & elem(&1, 0))
    result == (key in keys)
  end

  def postcondition(_state, {:call, FakeTime, :advance_time, _}, result) do
    result
  end
end
