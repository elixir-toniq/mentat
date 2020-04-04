defmodule Mentat.Janitor do
  @moduledoc false
  # Janitor service to periodically clean up caches
  use GenServer

  require Logger

  def start_link(args) do
    name = args[:name] || raise ArgumentError, "Mentat.Janitor must be started with a name"
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def init(args) do
    data = %{
      interval: args[:interval],
      cache: args[:cache]
    }

    Process.send_after(self(), :clean, data.interval)

    {:ok, data}
  end

  def handle_info(:clean, data) do
    Process.send_after(self(), :clean, data.interval)

    start_time = System.monotonic_time()
    count      = Mentat.remove_expired(data.cache)
    end_time   = System.monotonic_time()
    delta      = System.convert_time_unit(end_time - start_time, :native, :microsecond)

    :telemetry.execute(
      [:mentat, :janitor, :cleanup],
      %{latency: delta, total_removed_keys: count},
      %{cache: data.cache}
    )

    {:noreply, data}
  end
end

