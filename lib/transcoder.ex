defmodule JSONC.Transcoder do
  import JSONC.Parser

  def transcode!(content) when is_binary(content) do
    case transcode(content) do
      {:ok, result} -> result
      {:error, reason} -> raise reason
    end
  end

  def transcode(content) when is_binary(content) do
    case parse(content) do
      {:ok, %{type: :root, value: value}} ->
        {:ok, encode_value(value)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_value(value, level \\ 1) when is_map(value) do
    case value do
      %{type: :object, value: object_node} ->
        "{\n#{String.duplicate(" ", level * 4)}#{encode_object(object_node, level)}\n#{String.duplicate(" ", (level - 1) * 4)}}"

      %{type: :array, value: array_node} ->
        "[\n#{String.duplicate(" ", level * 4)}#{encode_array(array_node, level)}\n#{String.duplicate(" ", (level - 1) * 4)}]"

      %{type: :number, subtype: :integer, value: integer} ->
        Integer.to_string(integer)

      %{type: :number, subtype: :float, value: float} ->
        Float.to_string(float)

      %{type: :string, subtype: _, value: string} ->
        string =
          string
          |> String.replace("\n", "\\n")
          |> String.replace("\t", "\\t")
          |> String.replace("\r", "\\r")
          |> String.replace("\v", "\\v")
          |> String.replace("\b", "\\b")
          |> String.replace("\f", "\\f")

        "\"#{string}\""

      %{type: :boolean, value: boolean} ->
        boolean |> to_string()

      %{type: nil} ->
        "null"
    end
  end

  defp encode_object(node, level) when is_map(node) do
    node
    |> Enum.sort(fn {_, v1}, {_, v2} -> sort_values(v1, v2) end)
    |> Enum.map(fn {k, v} -> "\"#{k}\": #{encode_value(v, level + 1)}" end)
    |> Enum.join(",\n#{String.duplicate(" ", level * 4)}")
  end

  defp encode_array(node, level) when is_list(node) do
    node
    |> Enum.sort(&sort_values/2)
    |> Enum.map(fn v -> "#{encode_value(v, level + 1)}" end)
    |> Enum.join(",\n#{String.duplicate(" ", level * 4)}")
  end

  defp sort_values(%{place: {v1_line, v1_column}}, %{place: {v2_line, v2_column}}) do
    cond do
      v1_line > v2_line ->
        false

      v1_line == v2_line ->
        cond do
          v1_column > v2_column -> false
          true -> true
        end

      true ->
        true
    end
  end
end
