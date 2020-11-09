defmodule MentatTest do
  use ExUnit.Case

  setup do
    start_supervised({Mentat, name: TestCache})

    {:ok, cache: TestCache}
  end

  test "stores data for a given ttl", %{cache: cache} do
    assert Mentat.get(cache, :key) == nil
    assert Mentat.put(cache, :key, "value", ttl: 20)
    assert Mentat.get(cache, :key) == "value"

    :timer.sleep(30)
    assert Mentat.get(cache, :key) == nil
    assert Mentat.keys(cache) == [:key]
    Mentat.remove_expired(cache)
    assert Mentat.keys(cache) == []
  end

  describe "fetch/2" do
    test "returns data it finds in cache", %{cache: cache} do
      assert Mentat.fetch(cache, :key, fn _ ->
        {:commit, 3}
      end) == 3
      assert Mentat.fetch(cache, :key, fn _ -> {:commit, 4} end) == 3
      Mentat.purge(cache)
      assert Mentat.fetch(cache, :key, fn _ -> {:ignore, :error} end) == :error
      assert Mentat.get(cache, :key) == nil

      assert Mentat.fetch(cache, :key, [ttl: 20], fn _ -> {:commit, 5} end) == 5
      assert Mentat.get(cache, :key) == 5
      :timer.sleep(30)
      assert Mentat.get(cache, :key) == nil
      Mentat.remove_expired(cache)
      assert Mentat.keys(cache) == []
    end
  end

  describe "delete/2" do
    test "removes the key from the cache", %{cache: cache} do
      assert Mentat.put(cache, :key, "value") == true
      assert Mentat.get(cache, :key) == "value"
      assert Mentat.delete(cache, :key) == true
      assert Mentat.get(cache, :key) == nil
      assert Mentat.delete(cache, :key) == true
    end
  end

  describe "touch/2" do
    test "updates a cache key's inserted_at time", %{cache: cache} do
      assert Mentat.put(cache, :key, "value") == true
      now = System.monotonic_time(:millisecond)
      assert Mentat.touch(cache, :key) == true

      [{:key, _, ts, _}] = :ets.lookup(cache, :key)
      assert ts >= now
    end

    test "returns false if the key does not exist", %{cache: cache} do
      assert Mentat.touch(cache, :key) == false
    end

    test "extends a keys ttl", %{cache: cache} do
      assert Mentat.put(cache, :key, "value", ttl: 500)
      :timer.sleep(200)

      Mentat.touch(cache, :key)

      # sleep more than the expected 500ms timeout (200 + 400) == 600
      # The key should still be there and not have been evicted
      :timer.sleep(400)

      assert Mentat.get(cache, :key) == "value"
    end
  end

  describe "configuration" do
    test "additional :ets arguments can be passed via :ets_args" do
      stop_supervised(Mentat)
      name = ConcurrentCache
      start_supervised({Mentat, name: name, ets_args: [read_concurrency: true]})
      info = :ets.info(name)
      assert Keyword.fetch!(info, :read_concurrency)
    end
  end

  describe "limits" do
    test "caches can have fixed limits" do
      stop_supervised(Mentat)
      start_supervised({Mentat, name: LimitCache, limit: [size: 10, reclaim: 0.1]})

      for i <- 0..20 do
        Mentat.put(LimitCache, i, i)
        :timer.sleep(10)
      end

      :timer.sleep(10)

      assert :ets.info(LimitCache, :size) == 10
      keys = Mentat.keys(LimitCache)
      assert Enum.sort(keys) == [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
    end

    test "limits can be configured to reclaim a percentage of keys" do
      stop_supervised(Mentat)
      start_supervised({Mentat, name: LimitCache, limit: [size: 10, reclaim: 0.5]})

      for i <- 0..9 do
        Mentat.put(LimitCache, i, i)
        :timer.sleep(10)
      end

      # Exceed the limit and wait for items to be reclaimed
      Mentat.put(LimitCache, 10, 10)

      :timer.sleep(10)

      assert :ets.info(LimitCache, :size) == 6
      keys = Mentat.keys(LimitCache)
      assert Enum.sort(keys) == [5, 6, 7, 8, 9, 10]
    end
  end

  describe "default ttls" do
    test "TTLs can be defined for all keys" do
      stop_supervised(Mentat)
      start_supervised({Mentat, name: TTLCache, ttl: 20})

      Mentat.put(TTLCache, :key, :value)
      :timer.sleep(30)

      assert Mentat.get(TTLCache, :key) == nil
    end
  end
end
