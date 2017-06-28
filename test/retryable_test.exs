defmodule RetryableTest do
  use ExUnit.Case
  doctest Retryable

  test "call: successful outcome" do
    # without a handler, just passes the result back as a success
    result = Retryable.call(
      work: fn -> {:ok, :all_good} end
    )

    assert result == {:ok, :all_good}

    # with a handler, processes its response, returning as expected
    result = Retryable.call(
      work: fn -> {:ok, :all_good} end,
      on_success: fn (attempt, :all_good) -> {:return, attempt} end
    )

    assert result == {:ok, 1}
  end

  test "call: error outcome" do
    # without any handler, just passes the error along as a failure
    result = Retryable.call(
      work: fn -> {:error, :not_good} end
    )

    assert result == {:error, :not_good}

    # with a handler, processes its response, returning as expected
    result = Retryable.call(
      work: fn -> {:error, :not_good} end,
      on_error: fn (attempt, :not_good) -> {:fail, attempt} end
    )

    assert result == {:error, 1}
  end

  test "call: timeout" do
    # without any handler, just passes the timeout along as a failure
    result = Retryable.call(
      timeout: 100,
      work: fn -> :timer.sleep(150) end
    )

    assert result == {:error, :timeout}

    # with a handler, processes its response, returning as expected
    result = Retryable.call(
      timeout: 100,
      work: fn -> :timer.sleep(150) end,
      on_timeout: fn (_attempt, _) -> {:fail, :too_long} end
    )

    assert result == {:error, :too_long}
  end

  test "call: retrying" do
    start_time = :erlang.monotonic_time(:millisecond)

    result = Retryable.call(
      work: fn ->
        time_now = :erlang.monotonic_time(:millisecond)
        if time_now - start_time > 500 do
          {:ok, :is_working_now}
        else
          {:error, :is_broken}
        end
      end,
      on_error: fn
        (1, :is_broken) -> {:retry, 100}
        (2, :is_broken) -> {:retry, 100}
        (3, :is_broken) -> {:retry, 100}
        (4, :is_broken) -> {:retry, 100}
        (5, :is_broken) -> {:retry, 100}
      end,
      on_success: fn (6, :is_working_now) -> {:return, :yay} end
    )

    assert result == {:ok, :yay}
  end


  test "cast: successful outcome" do
    id = Retryable.cast(
      notify: self(),
      work: fn -> {:ok, :all_good} end
    )

    result = receive do
      {^id, result} -> result
    end

    assert result == {:ok, :all_good}
  end

  test "cast: error outcome" do
    id = Retryable.cast(
      notify: self(),
      work: fn -> {:error, :not_good} end
    )

    result = receive do
      {^id, result} -> result
    end

    assert result == {:error, :not_good}
  end

  test "cast: timeout" do
    id = Retryable.cast(
      notify: self(),
      timeout: 100,
      work: fn -> :timer.sleep(150) end
    )

    result = receive do
      {^id, result} -> result
    end

    assert result == {:error, :timeout}
  end
end
