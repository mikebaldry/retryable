defmodule RetryableTest do
  use ExUnit.Case
  doctest Retryable

  require Retryable

  test "work complete sucessfully" do
    retryable = Retryable.attempt do
      {:ok, :all_good}
    rescue
      {:ok, _result} -> :ok
    end

    assert_receive {^retryable, {:ok, {:ok, :all_good}}}, 100
  end

  test "work fails" do
    retryable = Retryable.attempt do
      {:error, :not_good}
    rescue
      {:error, err} -> {:error, err}
    end

    assert_receive {^retryable, {:error, :not_good}}, 100
  end

  test "work times out" do
    retryable = Retryable.attempt do
      Process.sleep(200)
    rescue
      {:timeout, 50} -> {:error, :timedout}
    end

    assert_receive {^retryable, {:error, :timedout}}, 100
  end
end
