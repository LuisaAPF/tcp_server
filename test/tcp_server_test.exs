defmodule TCPServerTest do
  use ExUnit.Case

  @user_port Application.get_env(:server, :ports)[:user]
  @event_port Application.get_env(:server, :ports)[:event_source]
  @ip {127, 0, 0, 1}

  defp disconnect_clients(clients) do
    for client <- clients do
      :ok = :gen_tcp.close(client)
    end
  end

  describe "The TCP server" do
    test "allows clients to connect on both available ports" do
      inactive_port = 5000
      # Connect 2 user clients and 1 event client
      assert {:ok, u1} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0, active: false])
      assert {:ok, u2} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0, active: false])
      assert {:ok, evt} = :gen_tcp.connect(@ip, @event_port, [:binary, packet: 0, active: false])
      assert {:error, _reason} = :gen_tcp.connect(@ip, inactive_port, [:binary, packet: 0, active: false])

      disconnect_clients([u1, u2, evt])
    end

    test "sends an event received on @source_port to a client connected on @user_port" do
      # A user connects on port @user_port
      {:ok, user} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0, active: false])
      # The connected user sends its id to the server
      user_payload = "50\n"
      :ok = :gen_tcp.send(user, user_payload)

      # An event source connects on port @event_port
      {:ok, event_source} = :gen_tcp.connect(@ip, @event_port, [:binary, packet: 0, active: false])
      # The connected event source sends a broadcast event to the server
      event_payload = "1|B\n"
      :ok = :gen_tcp.send(event_source, event_payload)

      # Make sure the connected user received the event
      assert {:ok, ^event_payload} = :gen_tcp.recv(user, 0, 2000)
      # Make sure the event source did not receive the event
      assert {:error, _} = :gen_tcp.recv(event_source, 0, 2000)

      disconnect_clients([user, event_source])
    end

    test "ignores an event sent on @user_port" do
      # A user connects on port @user_port
      {:ok, user} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0, active: false])
      # The connected user sends its id to the server
      user_payload = "50\n"
      :ok = :gen_tcp.send(user, user_payload)

      # The connected user tries to broadcast an event
      event_payload = "1|B\n"
      :ok = :gen_tcp.send(user, event_payload)

      # Make sure the event is not received by the connected user
      assert {:error, _} = :gen_tcp.recv(user, 0, 2000)

      disconnect_clients([user])
    end

    test "does not foward events to a user connected on @event_port" do
      # A user connects on port @event_port
      {:ok, user} = :gen_tcp.connect(@ip, @event_port, [:binary, packet: 0, active: false])
      # The connected user sends its id to the server
      user_payload = "50\n"
      :ok = :gen_tcp.send(user, user_payload)

      # An event source connects on port @event_port
      {:ok, event_source} = :gen_tcp.connect(@ip, @event_port, [:binary, packet: 0, active: false])
      # The connected event source sends a broadcast event to the server
      event_payload = "1|B\n"
      :ok = :gen_tcp.send(event_source, event_payload)

      # Make sure the connected user did not receive the event
      assert {:error, _} = :gen_tcp.recv(user, 0, 2000)

      disconnect_clients([user, event_source])
    end
  end
end
