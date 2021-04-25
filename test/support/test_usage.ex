defmodule Mentat.TestUsage do
  @moduledoc false
  # This module is here to trick dialyzer into actually maybe potentially
  # finding a bug possibly.

  def start_link do
    Mentat.start_link(name: __MODULE__)
  end

  def get(key) do
    case Mentat.get(__MODULE__, key) do
      nil -> :error
      term -> term
    end
  end

  def fetch(key) do
    Mentat.fetch(__MODULE__, key, [], fn k ->
      if k do
        {:commit, 123}
      else
        {:ignore, 123}
      end
    end)
  end

  def put(key, value) do
    true = Mentat.put(__MODULE__, key, value)
  end

  def touch(key) do
    true = Mentat.touch(__MODULE__, key)
  end

  def delete(key) do
    true = Mentat.delete(__MODULE__, key)
  end

  def keys do
    keys = Mentat.keys(__MODULE__)
    true = is_list(keys)
  end

  def purge do
    true = Mentat.purge(__MODULE__)
  end
end
