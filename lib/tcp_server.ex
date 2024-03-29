defmodule TCPServer do
  use GenServer
  require Logger

  @moduledoc """
  This module starts a TCP server, which listens on the available ports listed in
  the config file. As soon as the connections are open, it starts accepting
  incoming client connections.
  It expects to receive from user clients (those connected on the user port) an
  id, so that it can decide for which user(s) an incoming message was intended.
  It also expects an event source to connect on the event source port and to receive
  data following a pre-determined pattern.
  """

  def start_link(opts) do
    opts = [name: __MODULE__] |> Keyword.merge(opts)

    # Holds the 2 open sockets
    initial_state = %{
      sockets: [],
    }

    GenServer.start_link(__MODULE__, initial_state, opts)
  end

  @impl true
  def init(initial_state) do
    Process.flag(:trap_exit, true)

    open_sockets =
      Enum.reduce(available_ports(), [], fn {_owner, port}, acc ->
        {:ok, socket} = open_connection(port)
        [socket | acc]
      end)

    state = Map.put(initial_state, :sockets, open_sockets)

    Logger.info "TCP server started"
    {:ok, state}
  end

  defp available_ports() do
    Application.get_env(:server, :ports)
  end

  defp open_connection(port) do
    case :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true, keepalive: true]) do
      {:ok, socket} ->
        Logger.info "Connection open on port #{port}"
        {:ok, _pid} = Task.Supervisor.start_child(TCPServer.TaskSupervisor, fn -> accept_connections(socket, port) end)
        {:ok, socket}

      {:error, reason} ->
        Logger.error("Connection not open: #{reason}")
        {:error, reason}
    end
  end

  defp accept_connections(socket, server_port) do
    case :gen_tcp.accept(socket) do
      {:ok, client} ->
        {:ok, _pid} = Task.Supervisor.start_child(TCPServer.TaskSupervisor, fn -> transmit_data(client, server_port) end)
        accept_connections(socket, server_port)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def event_payload_regex() do
    ~r/^(?<sequence>[[:digit:]]+)\|(?<type>[[:upper:]])\|*(?<from_user>[[:digit:]]*)\|*(?<to_user>[[:digit:]]*)\s$/
  end

  defp transmit_data(socket, server_port) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        user_payload_regex = ~r/^(?<id>[[:digit:]]+)\s$/

        cond do
          # A user id was received on the user port
          server_port == available_ports()[:user] && Regex.match?(user_payload_regex, data) ->
            %{"id" => id} = Regex.named_captures(user_payload_regex, data)
            # Add this client to the state of the UserClientInfo genserver
            GenServer.call(UserClientInfo, {:add_client, socket, id})

          # An event payload was received on the event source port
          server_port == available_ports()[:event_source] && Regex.match?(event_payload_regex(), data) ->
            %{"sequence" => sequence} = Regex.named_captures(event_payload_regex(), data)
            # Let the Notifier module manage it.
            :ok = GenServer.call(Notifier, {:new_event, data, String.to_integer(sequence)})

          true ->
            # Anything else was received
            Logger.info("Could not process #{inspect data}")
            :ok
        end
        # Continue the transmission loop
        transmit_data(socket, server_port)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def terminate(_reason, state) do
    for socket <- state.sockets do
      :ok = :gen_tcp.close(socket)
    end
  end
end
