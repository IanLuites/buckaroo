defmodule BuckaroTest do
  use ExUnit.Case
  doctest Buckaro

  test "greets the world" do
    assert Buckaro.hello() == :world
  end
end
