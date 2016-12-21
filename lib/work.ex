defmodule Retryable.Work do
  require Logger

  defstruct [
    :retry_strategy,
    :retryable,

    :notify,
    :timeout_ms,

    :attempts,
    :timer,

    :monitor,
    :work_pid
  ]

  def start_link(opts) do
    work = %__MODULE__{
      attempts: 0,
      retry_strategy: Keyword.get(opts, :retry_strategy),
      retryable: Keyword.get(opts, :retryable),

      notify: Keyword.get(opts, :notify),
      timeout_ms: Keyword.get(opts, :timeout_ms)
    }

    GenServer.start_link(__MODULE__, work)
  end

  def init(work) do
    work = attempt_work(work)
    {:ok, work}
  end

  defp attempt_work(work) do
    Logger.debug("Starting work, attempt ##{work.attempts + 1}.")

    work_pid = self
    {pid, monitor} = spawn_monitor(fn ->
      result = work.retryable.()
      send(work_pid, {:work_complete, self, result}) end
    )

    timer = if work.timeout_ms do
      Process.send_after(self, :timeout_work, work.timeout_ms)
    end

    %{work | monitor: monitor, work_pid: pid, timer: timer}
  end

  defp process_result(work, result) do
    if work.timer do
      Process.cancel_timer(work.timer)
    end

    work = %{work |
      attempts: work.attempts + 1,
      monitor: nil,
      work_pid: nil,
      timer: nil
    }

    case work.retry_strategy.(work.attempts, result) do
      :ok ->
        Logger.debug("Work finished in #{work.attempts} attempt(s).")
        notify(work, {:ok, result})
        {:stop, :normal, work}
      {:retry, time_in_ms} ->
        Logger.debug("Retrying work in #{time_in_ms}ms.")
        Process.send_after(self, :retry_work, time_in_ms)
        {:noreply, work}
      {:error, error} ->
        Logger.debug "ERROR #{inspect error}"
        notify(work, {:error, error})
        {:stop, :normal, work}
      invalid_response ->
        raise "Expected either: :ok, {:retry, time_in_ms} or {:error, error}, got: #{invalid_response}."
        {:stop, :kill, work}
    end
  end

  defp notify(work, result) do
    if is_pid(work.notify) do
      send work.notify, {self, result}
    end
  end

  def timeout_work(work) do
    Logger.debug "Work didn't complete within #{work.timeout_ms}ms."

    Process.exit(work.work_pid, :kill)
    process_result(work, {:timeout, work.timeout_ms})
  end

  def handle_info(:retry_work, work) do
    {:noreply, attempt_work(work)}
  end

  def handle_info(:timeout_work, work) do
    timeout_work(work)
  end

  def handle_info({:work_complete, pid, result}, work) do
    if work.work_pid == pid do
      process_result(work, result)
    else
      {:noreply, work}
    end
  end

  def handle_info({:DOWN, monitor, :process, pid, reason}, work) do
    if work.monitor == monitor && work.work_pid == pid && reason != :normal do
      process_result(work, {:error, reason})
    else
      {:noreply, work}
    end
  end

  def terminate(_reason, _state) do

  end
end
