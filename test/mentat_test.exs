defmodule MentatTest do
  use ExUnit.Case

  test "stores data for a given ttl" do
    {:ok, _cache} = Mentat.start_link(name: TestCache)

    assert Mentat.get(TestCache, :key) == nil
    assert Mentat.put(TestCache, :key, "value", ttl: 20)
    assert Mentat.get(TestCache, :key) == "value"

    :timer.sleep(30)
    assert Mentat.get(TestCache, :key) == nil
    assert Mentat.keys(TestCache) == [:key]
    Mentat.remove_expired(TestCache)
    assert Mentat.keys(TestCache) == []
  end

  describe "fetch/2" do
    setup do
      start_supervised({Mentat, name: TestCache})

      {:ok, cache: TestCache}
    end

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
end
