defmodule NotifierTest do
  use ExUnit.Case

  @user_port Application.get_env(:server, :ports)[:user]
  @ip {127, 0, 0, 1}

  setup do
    # Start a test Notifier genserver
    {:ok, pid} = Notifier.start_link([name: :notifier_test_genserver])

    # Connect 2 user clients
    {:ok, u1} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0, active: false])
    {:ok, u2} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0, active: false])

    # The users send their respective ids to the server
    u1_id = "53"
    u2_id = "18"
    :ok = :gen_tcp.send(u1, "#{u1_id}\n")
    :ok = :gen_tcp.send(u2, "#{u2_id}\n")

    # To make sure the clients info will be saved
    Process.sleep(2000)

    on_exit(:some_ref, fn ->
      disconnect_clients([u1, u2])
      # Reset the state of the genserver that holds users info.
      GenServer.call(UserClientInfo, :empty_state)
    end)

    {:ok, pid: pid, u1: u1, u2: u2, u1_id: u1_id, u2_id: u2_id}
  end

  defp disconnect_clients(clients) do
    for client <- clients do
      :ok = :gen_tcp.close(client)
    end
  end

  describe "The Notifier server" do
    test "correctly notifies a connected user about `follow` events",
      %{pid: pid, u1: u1, u2: u2, u1_id: u1_id, u2_id: u2_id}
    do
      seq1 = 3
      seq2 = 1
      seq3 = 2
      event_1 = "#{seq1}|F|#{u2_id}|#{u1_id}\n"
      event_2 = "#{seq2}|F|55|#{u1_id}\n"
      event_3 = "#{seq3}|F|60|#{u1_id}\n"

      GenServer.call(pid, {:new_event, event_1, seq1})
      GenServer.call(pid, {:new_event, event_2, seq2})

      # The event with id 3 is saved on the genserver state, waiting for its
      # turn to be sent.
      assert %{
        events: [{seq1, event_1}],
        last_sent_id: seq2
      } == :sys.get_state(pid)

      # Only the user u1 should be notified about this event
      assert {:ok, event_2} == :gen_tcp.recv(u1, 0, 2000)
      refute {:ok, event_2} == :gen_tcp.recv(u2, 0, 2000)
      # This event should not have been sent yet, therefore should also not
      # have been received by any of the users.
      refute {:ok, event_1} == :gen_tcp.recv(u1, 0, 2000)
      refute {:ok, event_1} == :gen_tcp.recv(u2, 0, 2000)

      GenServer.call(pid, {:new_event, event_3, seq3})

      # Both events with sequences 2 and 3 should be sent.
      assert %{
        events: [],
        last_sent_id: seq1
      } == :sys.get_state(pid)

      assert {:ok, event_3 <> event_1} == :gen_tcp.recv(u1, 0, 2000)
    end

    test "correctly notifies all conected user clients about `broadcast` events",
      %{pid: pid, u1: u1, u2: u2}
    do
      seq1 = 3
      seq2 = 1
      seq3 = 2
      event_1 = "#{seq1}|B\n"
      event_2 = "#{seq2}|B\n"
      event_3 = "#{seq3}|B\n"

      GenServer.call(pid, {:new_event, event_1, seq1})
      GenServer.call(pid, {:new_event, event_2, seq2})

      # The event with id 3 is saved on the genserver state, waiting for its
      # turn to be sent.
      assert %{
        events: [{seq1, event_1}],
        last_sent_id: seq2
      } == :sys.get_state(pid)

      # Both connected users should be notified about this event
      assert {:ok, event_2} == :gen_tcp.recv(u1, 0, 2000)
      assert {:ok, event_2} == :gen_tcp.recv(u2, 0, 2000)
      # This event should not have been sent yet, therefore should also not
      # have been received by any of the users.
      refute {:ok, event_1} == :gen_tcp.recv(u1, 0, 2000)
      refute {:ok, event_1} == :gen_tcp.recv(u2, 0, 2000)

      GenServer.call(pid, {:new_event, event_3, seq3})

      # Both events with sequences 2 and 3 should be sent.
      assert %{
        events: [],
        last_sent_id: seq1
      } == :sys.get_state(pid)

      assert {:ok, event_3 <> event_1} == :gen_tcp.recv(u1, 0, 2000)
    end

    test "does not notify the connected user clients about `unfollow` events",
      %{pid: pid, u1: u1, u2: u2, u1_id: u1_id, u2_id: u2_id}
    do
      event = "1|U|#{u2_id}|#{u1_id}\n"

      GenServer.call(pid, {:new_event, event, 1})

      # None of the connected users should be notified about this event.
      refute {:ok, event} == :gen_tcp.recv(u1, 0, 2000)
      refute {:ok, event} == :gen_tcp.recv(u2, 0, 2000)
    end

    test "correctly notifies a connected user about `private message` events",
      %{pid: pid, u1: u1, u2: u2, u1_id: u1_id, u2_id: u2_id}
    do
      seq1 = 3
      seq2 = 1
      seq3 = 2
      event_1 = "#{seq1}|F|#{u2_id}|#{u1_id}\n"
      event_2 = "#{seq2}|F|55|#{u1_id}\n"
      event_3 = "#{seq3}|F|60|#{u1_id}\n"

      GenServer.call(pid, {:new_event, event_1, seq1})
      GenServer.call(pid, {:new_event, event_2, seq2})

      # The event with id 3 is saved on the genserver state, waiting for its
      # turn to be sent.
      assert %{
        events: [{seq1, event_1}],
        last_sent_id: seq2
      } == :sys.get_state(pid)

      # Only the user u1 should be notified about this event
      assert {:ok, event_2} == :gen_tcp.recv(u1, 0, 2000)
      refute {:ok, event_2} == :gen_tcp.recv(u2, 0, 2000)
      # This event should not have been sent yet, therefore should also not
      # have been received by any of the users.
      refute {:ok, event_1} == :gen_tcp.recv(u1, 0, 2000)
      refute {:ok, event_1} == :gen_tcp.recv(u2, 0, 2000)

      GenServer.call(pid, {:new_event, event_3, seq3})

      # Both events with sequences 2 and 3 should be sent.
      assert %{
        events: [],
        last_sent_id: seq1
      } == :sys.get_state(pid)

      assert {:ok, event_3 <> event_1} == :gen_tcp.recv(u1, 0, 2000)
    end

    test "correctly notifies all followers about a user's `status update` event",
      %{pid: pid, u1: u1, u2: u2, u1_id: u1_id, u2_id: u2_id}
    do
      follow_payload = "1|F|#{u2_id}|#{u1_id}\n"
      status_update_payload = "2|S|#{u1_id}\n"

      GenServer.call(pid, {:new_event, follow_payload, 1})

      assert {:ok, follow_payload} == :gen_tcp.recv(u1, 0, 2000)

      # At this point user 2 should be a follower of user 1, so it should
      # receive the status update event.

      GenServer.call(pid, {:new_event, status_update_payload, 2})

      assert {:ok, status_update_payload} == :gen_tcp.recv(u2, 0, 2000)
      refute {:ok, status_update_payload} == :gen_tcp.recv(u1, 0, 2000)
    end
  end
end
