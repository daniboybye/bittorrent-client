defmodule Bittorrent.Tracker do

  def first_request!(file_name, peer_id,port) do
    struct = file_name
    |> File.read!()
    |> Bencode.decode!()
         
    info_hash = hash(struct)
    bytes = all_bytes_in_torrent(struct)
    pieces_size = struct["info"]["pieces"] |> byte_size() |> div(20)
    torrent = %Bittorrent.Torrent.Struct{
      info_hash: info_hash,
      bytes: bytes,
      struct: struct,
      uploaded: 0, 
      downloaded: 0,
      pieces_size: pieces_size
    } 
    peers = request!(torrent, peer_id, port, "started")
    
    {torrent, peers}
  end

  #@spec request(map(), binary(), binary(), integer(), integer(), integer(), binary()) ::
   #       map() | no_result()
  def request!(%Bittorrent.Torrent.Struct{
    info_hash: info_hash,
    bytes: bytes,
    struct: struct,
    uploaded: uploaded, 
    downloaded: downloaded
    }, peer_id, port, event \\ "empty") do
    query =
      URI.encode_query(%{
        "info_hash" => info_hash,
        # urlencoded 20-byte string used as a unique ID for the client, 
        # generated by the client at startup
        "peer_id" => peer_id,
        "port" => to_string(port),
        "compact" => "true",
        # The total amount uploaded 
        # (since the client sent the 'started' event to the tracker)"""
        "uploaded" => uploaded,
        # The total amount downloaded 
        # (since the client sent the 'started' event to the tracker)"""
        "downloaded" => downloaded,
        # The number of bytes this client still has to download in base
        # ten ASCII. Clarification: 
        # The number of bytes needed to download to be 100% complete 
        # and get all the included files in the torrent.
        "left" => bytes,
        # started | completed | stopped | empty
        "event" => event
      })

    {:ok, %HTTPoison.Response{body: body}} =
      <<struct["announce"]::binary, "?", query::binary>>
      |> HTTPoison.get(timeout: 25_000, recv_timeout: 25_000)

    body
    |> Bencode.decode!()
    |> Map.fetch!("peers")
  end

  @spec hash(map()) :: binary() | no_return()
  defp hash(%{"info" => info}) do
    info
    |> Bencode.encode!()
    |> (&:crypto.hash(:sha, &1)).()
  end

  @spec hash(map()) :: pos_integer() | no_return()
  defp all_bytes_in_torrent(%{"info" => %{"files" => list}}) do
    Enum.reduce(list, 0, fn %{"length" => x}, acc -> x + acc end)
  end
end
