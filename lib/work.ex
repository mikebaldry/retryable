defmodule Retryable.Work do
  require Logger

  defstruct [
    :id,

    :work,

    :on_success,
    :on_error,
    :on_timeout,

    :when_complete,
    :timeout,

    :attempts,

    :enqueued_at,
    :started_at,
    :ended_at,

    :timer,
    :monitor,
    :pid
  ]

  def new(opts) do
    %__MODULE__{
      id: UUID.uuid4,
      attempts: 0,

      work: Keyword.fetch!(opts, :work),

      when_complete: Keyword.get(opts, :when_complete),
      timeout: Keyword.get(opts, :timeout),

      on_success: Keyword.get(opts, :on_success, fn (_, result) -> {:return, result} end),
      on_error: Keyword.get(opts, :on_error, fn (_, error) -> {:fail, error} end),
      on_timeout: Keyword.get(opts, :on_timeout, fn (_, :timeout) -> {:fail, :timeout} end)
    }
  end

  def enqueued(work) do
    %{work |
      enqueued_at: :erlang.monotonic_time(:millisecond)
    }
  end

  def started(work) do
    %{work |
      started_at: :erlang.monotonic_time(:millisecond)
    }
  end

  def ended(work) do
    %{work |
      ended_at: :erlang.monotonic_time(:millisecond)
    }
  end

  def next_attempt(work) do
    %{work |
      attempts: work.attempts + 1,
      monitor: nil,
      pid: nil,
      timer: nil
    }
  end

  def process(work) do
    log(work, "Starting work, attempt ##{work.attempts + 1}.")
    my_pid = self()

    {pid, monitor} = spawn_monitor(fn ->
      receive do
        :begin_work ->
          result = work.work.()
          send(my_pid, {:finished, result})
      end
    end)

    timer = if work.timeout do
      Process.send_after(my_pid, :timeout, work.timeout)
    end

    work = %{work | timer: timer, pid: pid, monitor: monitor}

    send(work.pid, :begin_work)

    response = await_response(work)
    {work, result} = process_response(work, response)
    process_result(work, result)
  end

  defp await_response(work) do
    monitor = work.monitor
    pid = work.pid

    receive do
      {:finished, {:ok, result}} ->
        cancel_timer(work)
        await_monitor_down(work, :normal)
        {:ok, result}

      {:finished, {:error, error}} ->
        cancel_timer(work)
        await_monitor_down(work, :normal)
        {:error, error}

      {:finished, unexpected_response} ->
        raise "Expected `work` to return with either `{:ok, result}` or `{:error, error}`, got: #{inspect unexpected_response}."

      :timeout ->
        Process.exit(work.pid, :kill)
        await_monitor_down(work, :killed)
        :timeout

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        cancel_timer(work)
        {:error, reason}
    end
  end

  defp process_response(work, {:ok, result}) do
    work = next_attempt(work)
    {work, work.on_success.(work.attempts, result)}
  end

  defp process_response(work, {:error, error}) do
    work = next_attempt(work)
    {work, work.on_error.(work.attempts, error)}
  end

  defp process_response(work, :timeout) do
    work = next_attempt(work)
    {work, work.on_timeout.(work.attempts, :timeout)}
  end

  defp process_result(work, {:return, result}) do
    work = ended(work)
    log(work, "Finished. Queuing for: #{work.started_at - work.enqueued_at}ms Processing for: #{work.ended_at - work.started_at}ms Attempts: #{work.attempts}.")
    complete_callback(work, {:ok, result})
  end

  defp process_result(work, {:retry, time_in_ms}) do
    log(work, "Retrying in #{time_in_ms}ms.")
    :timer.sleep(time_in_ms)
    process(work)
  end

  defp process_result(work, {:fail, error}) do
    log(work, "Failed, error: #{inspect error}.")
    complete_callback(work, {:error, error})
  end

  defp process_result(_work, invalid_response) do
    raise "Expected either: {:return, result}, {:retry, time_in_ms} or {:fail, error}, got: #{inspect invalid_response}."
  end

  defp await_monitor_down(work, reason) do
    monitor = work.monitor
    pid = work.pid

    receive do
      {:DOWN, ^monitor, :process, ^pid, ^reason} ->
        nil
      other_message ->
        log(work, "Unexpectedly recieved: #{inspect other_message}")
        await_monitor_down(work, reason)
    end
  end

  defp log(work, message) do
    Logger.debug("[Retryable][#{work.id}] #{message}")
  end

  defp cancel_timer(%Retryable.Work{timer: nil}), do: nil
  defp cancel_timer(%Retryable.Work{timer: timer}), do: Process.cancel_timer(timer)

  defp complete_callback(work, result) do
    if is_function(work.when_complete) do
      work.when_complete.(work.id, result)
    end
  end
end
