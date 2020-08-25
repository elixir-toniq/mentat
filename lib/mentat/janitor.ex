defmodule Mentat.Janitor do
  @moduledoc false
  # Janitor service to periodically clean up caches
  use GenServer

  require Logger

  def start_link(args) do
    name = args[:name] || raise ArgumentError, "Mentat.Janitor must be started with a name"
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def reclaim(name, num_of_keys) do
    GenServer.cast(name, {:reclaim, num_of_keys})
  end

  def init(args) do
    data = %{
      interval: args[:interval],
      cache: args[:cache]
    }

    Process.send_after(self(), :clean, data.interval)

    {:ok, data}
  end

  def handle_cast({:reclaim, count}, data) do
    start_time    = System.monotonic_time()
    removed_count = Mentat.remove_oldest(data.cache, count)
    end_time      = System.monotonic_time()
    delta         = end_time - start_time

    :telemetry.execute(
      [:mentat, :janitor, :reclaim],
      %{duration: delta, total_removed_keys: removed_count},
      %{cache: data.cache}
    )

    {:noreply, data}
  end

  def handle_info(:clean, data) do
    Process.send_after(self(), :clean, data.interval)

    start_time = System.monotonic_time()
    count      = Mentat.remove_expired(data.cache)
    end_time   = System.monotonic_time()
    delta      = end_time - start_time

    :telemetry.execute(
      [:mentat, :janitor, :cleanup],
      %{duration: delta, total_removed_keys: count},
      %{cache: data.cache}
    )

    {:noreply, data}
  end
end
