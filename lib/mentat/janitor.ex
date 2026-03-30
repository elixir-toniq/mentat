defmodule Mentat.Janitor do
  @moduledoc false
  # Janitor service to periodically clean up caches
  use GenServer

  require Logger

  def start_link(args) do
    name = args[:name] || raise ArgumentError, "Mentat.Janitor must be started with a name"
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def reclaim(name) do
    GenServer.cast(name, :reclaim)
  end

  def init(args) do
    data = %{
      interval: args[:interval],
      cache: args[:cache]
    }

    Process.send_after(self(), :clean, data.interval)

    {:ok, data}
  end

  def handle_cast(:reclaim, data) do
    config = Mentat.get_config(data.cache)

    # This logic is duplicated from `Mentat.put`. This is because we only
    # want to send this message from a calling process if there's a reason
    # to do a reclamation. But, multiple processes might detect this issue
    # simultaneously. If we don't check again here we will erroneously 
    # trigger multiple reclamations which can end up removing many more keys
    # than is intended.
    if Mentat.size(data.cache) > config.limit.size do
      start_time    = System.monotonic_time()
      count = ceil(config.limit.size * config.limit.reclaim)

      removed_count = Mentat.remove_oldest(data.cache, count)

      end_time      = System.monotonic_time()
      delta         = end_time - start_time

      :telemetry.execute(
        [:mentat, :janitor, :reclaim],
        %{duration: delta, total_removed_keys: removed_count},
        %{cache: data.cache}
      )
    end

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
