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
end
