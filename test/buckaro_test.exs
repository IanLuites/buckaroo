defmodule BuckarooTest do
  use ExUnit.Case
  doctest Buckaroo

  test "greets the world" do
    assert Buckaroo.hello() == :world
  end
end
