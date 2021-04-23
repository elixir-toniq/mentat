defmodule Mentat.FakeTime do
  @moduledoc false
  # Allows control over a fake monotonic clock which allows us to control
  # our property based tests.
  @key {__MODULE__, :time}

  def monotonic_time(_) do
    get_time()
  end

  def incr do
    :ok = set_time(get_time() + 1)
    true
  end

  def reset do
    set_time(0)
  end

  defp get_time do
    :persistent_term.get(@key)
  end

  defp set_time(time) do
    :persistent_term.put(@key, time)
  end
end
