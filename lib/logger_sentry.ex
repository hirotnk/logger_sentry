defmodule Logger.Backends.Sentry do
  @moduledoc """
  This module is the sentry backend for Logger and it can handle the event
  message from the Logger event server and push the log message to the sentry
  dashboard. This module have a set of interface functions:

    * get/set the log level
    * get/set the log metadata

  ## Config

  config example:

      config :logger,
        backends: [:console, Logger.Backends.File],
        sentry: [level: :error,
                 metadata: []
                ]

  We set the Applicaton configure of `logger`, and add it to `backends` list,
  the set log level as needed. So we could execute Logger interface functions
  as usas, and the sentry backend will push log message to the sentry dashboard.
  """

  @level_list [:debug, :info, :warn, :error]
  @metadata_list [:application, :module, :function, :file, :line, :pid]
  defstruct metadata: nil, level: nil, other_config: nil

  @doc """
  Get the backend log level.
  """
  @spec level :: :debug | :info | :warn | :error
  def level, do: :gen_event.call(Logger, __MODULE__, :level)

  @doc """
  Set the backend log level.
  """
  @spec level(:debug | :info | :warn | :error) :: :ok | :error_level
  def level(log_level) when log_level in @level_list do
    :gen_event.call(Logger, __MODULE__, {:level, log_level})
  end

  def level(_), do: :error_level

  @doc """
  Get the backend log metadata.
  """
  @spec metadata :: :all | list()
  def metadata, do: :gen_event.call(Logger, __MODULE__, :metadata)

  @doc """
  Set the backend log metadata.
  """
  @spec metadata(:all | list()) :: :error_metadata | :ok
  def metadata(:all) do
    :gen_event.call(Logger, __MODULE__, {:metadata, :all})
  end

  def metadata(meta_data) when is_list(meta_data) do
    case Enum.all?(meta_data, fn i -> Enum.member?(@metadata_list, i) end) do
      true -> :gen_event.call(Logger, __MODULE__, {:metadata, meta_data})
      false -> :error_metadata
    end
  end

  def metadata(_), do: :error_metadata

  @doc false
  def init(_) do
    config = Application.get_env(:logger, :sentry, [])
    {:ok, init(config, %__MODULE__{})}
  end

  @doc false
  def handle_call(:level, state) do
    {:ok, state.level, state}
  end

  def handle_call({:level, log_level}, state) do
    {:ok, :ok, %{state | level: log_level}}
  end

  def handle_call(:metadata, state) do
    {:ok, state.metadata, state}
  end

  def handle_call({:metadata, meta_data}, state) do
    {:ok, :ok, %{state | metadata: meta_data}}
  end

  @doc false
  def handle_event({log_level, _gl, {Logger, msg, _ts, md}}, %{level: status_log_level} = state) do
    case meet_level?(log_level, status_log_level) do
      true -> {:ok, log_event(log_level, md, msg, state)}
      _ -> {:ok, state}
    end
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  @doc false
  def handle_info(_, state) do
    {:ok, state}
  end

  @doc false
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  @doc false
  def terminate(_reason, _state) do
    :ok
  end

  @doc false
  defp init(config, state) do
    meta_data =
      config
      |> Keyword.get(:metadata, [])
      |> configure_metadata()

    state
    |> Map.put(:metadata, meta_data)
    |> Map.put(:level, Keyword.get(config, :level, :info))
  end

  @doc false
  defp configure_metadata(:all), do: :all
  defp configure_metadata(meta_data), do: Enum.reverse(meta_data)

  @doc false
  defp meet_level?(_log_level, nil), do: true
  defp meet_level?(log_level, min), do: Logger.compare_levels(log_level, min) != :lt

  if Mix.env() in [:test] do
    defp log_event(log_level, _md, msg, state) do
      case :ets.info(:__just_prepare_for_logger_sentry__) do
        :undefined -> :ignore
        _ -> :ets.insert(:__just_prepare_for_logger_sentry__, {log_level, msg})
      end

      state
    end
  else
    @doc false
    defp normalize_level(:warn), do: "warning"
    defp normalize_level(log_level), do: to_string(log_level)

    defp log_event(:error, md, msg, state) do
      {output, meta_data} = LoggerSentry.Sentry.generate_output(:error, md, msg)
      Sentry.capture_exception(output, LoggerSentry.Sentry.generate_opts(meta_data, msg))
      state
    end

    defp log_event(log_level, md, msg, state) do
      meta_data = [{:level, normalize_level(log_level)} | md]
      {output, meta_data} = LoggerSentry.Sentry.generate_output(log_level, meta_data, msg)
      Sentry.capture_message(output, LoggerSentry.Sentry.generate_opts(meta_data, msg))
      state
    end
  end

  # __end_of_module__
end
