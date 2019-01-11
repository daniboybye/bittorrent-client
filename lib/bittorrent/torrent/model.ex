defmodule Torrent.Model do
  use GenServer
  use Via

  @timeout_detect_the_speed 5 * 1_000
  @until_endgame 0
  @stopped Torrent.stopped()

  @spec start_link(Torrent.t()) :: GenServer.on_start()
  def start_link(torrent),
    do: GenServer.start_link(__MODULE__, torrent, name: via(torrent.hash))

  @spec has_hash?(Torrent.hash()) :: boolean()
  def has_hash?(hash),
    do: !!GenServer.whereis(via(hash))

  @spec downloaded?(Torrent.hash()) :: boolean()
  def downloaded?(hash),
    do: GenServer.call(via(hash), :downloaded?)

  @spec get(Torrent.hash(), atom() | [atom()]) :: any()
  def get(hash, key),
    do: GenServer.call(via(hash), {:get, key})

  @spec get(Torrent.hash()) :: Torrent.t()
  def get(hash),
    do: GenServer.call(via(hash), :get)

  @spec uploaded_subpiece(Torrent.hash(), non_neg_integer()) :: :ok
  def uploaded_subpiece(hash, bytes_size),
    do: GenServer.cast(via(hash), {:uploaded_subpiece, bytes_size})

  @spec downloaded_piece(Torrent.hash(), Torrent.index()) :: :ok
  def downloaded_piece(hash, index),
    do: GenServer.cast(via(hash), {:downloaded_piece, index})

  def update_event(hash),
    do: GenServer.cast(via(hash), :update_event)

  def piece_length(hash, index),
    do: GenServer.call(via(hash), {:piece_length, index})

  def set_peer_status(hash, status),
    do: GenServer.cast(via(hash), {:set_peer_status, status})

  def init(torrent) do
    message_for_next_detection(torrent)
    {:ok, torrent}
  end

  def handle_call(:get, _, torrent),
    do: {:reply, torrent, torrent}

  def handle_call({:get, key}, _, torrent) when is_atom(key),
    do: {:reply, do_get(key, torrent), torrent}

  def handle_call({:get, keys}, _, torrent) when is_list(keys),
    do: {:reply, Enum.map(keys, &do_get(&1, torrent)), torrent}

  def handle_call({:piece_length, index}, _, torrent),
    do: {:reply, do_piece_length(index, torrent), torrent}

  def handle_call(:downloaded?, _, torrent),
    do: {:reply, torrent.left === 0, torrent}

  def handle_cast({:downloaded_piece, index}, torrent) do
    length = do_piece_length(index, torrent)

    torrent = %Torrent{
      torrent
      | downloaded: torrent.downloaded + length,
        left: torrent.left - length
    }

    torrent =
      with %Torrent{left: 0} <- torrent do
        IO.puts("downloaded #{torrent.struct["info"]["name"]}")
        %Torrent{torrent | event: Torrent.completed(), peer_status: :seed}
      end

    {:noreply, torrent}
  end

  def handle_cast({:uploaded_subpiece, bytes_size}, torrent),
    do: {:noreply, Map.update!(torrent, :uploaded, &(&1 + bytes_size))}

  def handle_cast({:set_peer_status, status}, torrent),
    do: {:noreply, %Torrent{torrent | peer_status: status}}

  def handle_cast(:update_event, %Torrent{event: @stopped} = torrent),
    do: {:noreply, torrent}

  def handle_cast(:update_event, %Torrent{left: 0} = torrent),
    do: {:noreply, %Torrent{torrent | event: Torrent.completed()}}

  def handle_cast(:update_event, torrent),
    do: {:noreply, %Torrent{torrent | event: Torrent.empty()}}

  def handle_info({:detected_the_speed, download, upload}, torrent) do
    message_for_next_detection(torrent)

    speed = %{
      download: detected_the_speed(torrent.downloaded, download),
      uplaod: detected_the_speed(torrent.uploaded, upload)
    }

    {:noreply, %Torrent{torrent | speed: speed}}
  end

  defp do_get(:bytes_size, %Torrent{downloaded: n, left: m}),
    do: n + m

  defp do_get(:pieces_count, %Torrent{last_index: i}),
    do: i + 1

  defp do_get(:piece_length, torrent),
    do: torrent.struct["info"]["piece length"]

  defp do_get(:mode, %Torrent{left: 0}), do: nil

  defp do_get(:mode, torrent) do
    if torrent.left <= @until_endgame * do_get(:piece_length, torrent),
      do: :endgame
  end

  # else mode: nil

  defp do_get(key, torrent), do: Map.get(torrent, key)

  # Kb/s
  defp detected_the_speed(current, old),
    do: (current - old) / (@timeout_detect_the_speed / 1_000)

  defp message_for_next_detection(torrent) do
    message = {:detected_the_speed, torrent.downloaded, torrent.uploaded}
    Process.send_after(self(), message, @timeout_detect_the_speed)
  end

  defp do_piece_length(index, %Torrent{last_index: last_index} = torrent)
       when index === last_index,
       do: torrent.last_piece_length

  defp do_piece_length(_, torrent),
    do: do_get(:piece_length, torrent)
end
