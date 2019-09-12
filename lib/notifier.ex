defmodule Notifier do
  use GenServer
  require Logger

  @moduledoc """
  This module is responsible for sending event notifications to connected users.
  Because events should be sent in ascending order of event id, this module stores
  in its genserver state the events that are out of order, until they can be sent.
  """

  def start_link(opts) do
    opts = [name: __MODULE__] |> Keyword.merge(opts)

    # Holds the events that are waiting to be sent and the id of the last sent
    # event.
    # Ex:
    # %{
    #   events: [{5, "5|S|9"}, {6, "6|F|3|10"}],
    #   last_sent_id: 3
    # }
    initial_state = %{
      events: [],
      last_sent_id: 0
    }

    GenServer.start_link(__MODULE__, initial_state, opts)
  end

  @impl true
  def init(initial_state) do
    {:ok, initial_state}
  end

  @doc """
  Handles the receiving of a new event. In case the new event id is sequencial to
  the last_sent_id, the event is sent to the interested users right away.
  Otherwise, it's added to the genserver state.
  If there are other events waiting to be sent that are sequencial to the just
  sent event id, they are also sent.
  """
  @impl true
  def handle_call({:new_event, event, event_id}, _from, state) do
    new_state =
      if (event_id - state.last_sent_id > 1) do
        # There are missing ids between the new event and the last sent event,
        # so save the events in the state and do not notify the user yet.
        Map.put(state, :events, [{event_id, event} | state.events])
      else
        # The new event id is the next one in sequence after the last sent event id,
        # so the user can be notified.
        notify(event)

        # Update the last sent id in the state.
        state = Map.put(state, :last_sent_id, event_id)

        # Check if that are other events in the sequence that can also be sent.
        sorted_events = Enum.sort(state.events)

        # The initial accumulator is the current state. On each iteration,
        # if an event is sent, the corresponding entry is removed from
        # the events list in the accumulator and the value of last_sent_id is
        # updated.
        Enum.reduce_while(sorted_events, state, fn {evt_id, evt}, acc ->
          if (evt_id - acc.last_sent_id == 1) do
            notify(evt)
            # Remove the entry corresponding to the just sent event
            # and update the value of last_sent_id
            acc =
              acc
              |> Map.put(:events, List.delete(acc.events, {evt_id, evt}))
              |> Map.put(:last_sent_id, evt_id)

            {:cont, acc}
          else
            {:halt, acc}
          end
        end)
      end

    {:reply, :ok, new_state}
  end

  @doc """
  Sends an event to the interested users.
  """
  defp notify(event) do
    event_payload_regex = TCPServer.event_payload_regex()

    %{"type" => type, "to_user" => to_user, "from_user" => from_user}
      = Regex.named_captures(event_payload_regex, event)

    case type do
      "B" ->
        # `Broadcast` event
        clients = GenServer.call(UserClientInfo, :get_all_clients)
        Enum.each(clients, fn client ->
          :gen_tcp.send client, event
        end)

      "F" ->
        # `Follow` event
        client = GenServer.call(UserClientInfo, {:get_client, to_user})
        if (not is_nil(client)) do
          :gen_tcp.send client, event
        end
        :ok = GenServer.call(UserClientInfo, {:add_follower, to_user, from_user})

      "P" ->
        # `Private message` event
        client = GenServer.call(UserClientInfo, {:get_client, to_user})
        if (not is_nil(client)) do
          :gen_tcp.send client, event
        end

      "S" ->
        # `Status update` event
        followers = GenServer.call(UserClientInfo, {:get_followers, from_user})
        Enum.each(followers, fn follower_id ->
          client = GenServer.call(UserClientInfo, {:get_client, follower_id})
          if (not is_nil(client)) do
            :gen_tcp.send client, event
          end
        end)

      "U" ->
        # `Unfollow` event
        :ok = GenServer.call(UserClientInfo, {:remove_follower, to_user, from_user})

      _ ->
        Logger.info("No event type matching #{type}")
    end
  end
end
