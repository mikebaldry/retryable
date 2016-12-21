defmodule Retryable do
  defmodule App do
    use Application

    # See http://elixir-lang.org/docs/stable/elixir/Application.html
    # for more information on OTP Applications
    def start(_type, _args) do
      import Supervisor.Spec, warn: false

      # Define workers and child supervisors to be supervised
      children = [
        # Starts a worker by calling: Retryable.Worker.start_link(arg1, arg2, arg3)
        supervisor(Retryable.WorkSupervisor, []),
      ]

      # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
      # for other strategies and supported options
      opts = [strategy: :one_for_one, name: Retryable.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end

  defmacro attempt(opts \\ []) do
    do_block = Keyword.get(opts, :do)
    rescue_block = Keyword.get(opts, :rescue)

    unless do_block do
      compile_error(__ENV__, "You must pass a do block")
    end

    unless rescue_block do
      compile_error(__ENV__, "You must pass a rescue block")
    end

    looks_like_case_inner = is_list(rescue_block) && Enum.all?(rescue_block, fn
      {:"->", _, _} -> true
      _ -> false
    end)

    unless looks_like_case_inner do
      compile_error(__ENV__, "Your rescue block must be like:\n\tresult_match_one -> response\n\tresult_match_two -> response")
    end

    timeout_clause =
      rescue_block
      |> Enum.find(fn
        {:"->", _, [[timeout: _], _]} -> true
        _ -> false
      end)

    timeout_ms = if timeout_clause do
      {:"->", _, [[timeout: timeout_ms], _]} = timeout_clause
      timeout_ms
    else
      nil
    end

    do_fn = quote do
      fn -> unquote(do_block) end
    end

    rescue_fn = quote do
      fn (var!(attempts), result) ->
        case result do
          unquote(rescue_block)
        end
      end
    end

    quote do
      Retryable.attempt_work(
        retry_strategy: unquote(rescue_fn),
        retryable: unquote(do_fn),
        notify: self,
        timeout_ms: unquote(timeout_ms)
      )
    end
  end

  @doc """
    Creates a new piece of work to be carried out.
  """
  def attempt_work(opts \\ []) do
    {:ok, pid} = Retryable.WorkSupervisor.attempt(opts)
    pid
  end

  @doc """
    Adds jitter to a retry time so that many failing jobs won't all retry at
    the same time
  """
  def jitter(amount_ms), do: jitter(0, amount_ms)
  def jitter(value_ms, amount_ms) do
    value_ms + round(:rand.uniform * amount_ms)
  end

  @doc """
    Adds an exponential backoff to a retry time based on the number of attempts
  """
  def exponential_backoff(value_ms, attempts, exp_base \\ 2) do
    value_ms + round((:math.pow(exp_base, attempts) * 1000))
  end

  defp compile_error(caller, desc) do
    raise CompileError, file: caller.file, line: caller.line, description: desc
  end
end
