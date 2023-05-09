defmodule JSONC.Parser do
  @whitespace ["\v", "\f", "\r", "\n", "\s", "\t", "\b"]

  @invalid_for_generics [
    "{",
    "}",
    "[",
    "]",
    ",",
    ":",
    "\\",
    "/",
    "\"",
    "`",
    "'",
    "~",
    "*",
    "(",
    ")",
    "<",
    ">",
    "!",
    "?",
    "@",
    "#",
    "$",
    "%",
    "^",
    "&",
    "=",
    ";",
    "|"
  ]

  def parse!(content) when is_binary(content) do
    case parse(content) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise reason
    end
  end

  def parse(content) when is_binary(content) do
    case parse_value(content) do
      {result, ""} -> {:ok, %{type: :root, value: result}}
      :error -> {:error, ""}
    end
  end

  defp parse_value(content) do
    <<current::utf8, rest::binary>> = skip_whitespace(content)

    case <<current::utf8>> do
      "[" -> parse_array(rest)
      "{" -> parse_object(rest)
      "`" -> parse_string(rest, :multi)
      "\"" -> parse_string(rest, :single)
      _ -> parse_generic("#{<<current::utf8>>}#{rest}")
    end
  end

  defp parse_array(_, _ \\ [])

  defp parse_array("", _) do
    IO.puts("FLAG A")
    :error
  end

  defp parse_array(content, list) do
    <<current::utf8, rest::binary>> = skip_whitespace(content)

    cond do
      <<current::utf8>> == "]" ->
        rest = skip_whitespace(rest)
        {%{type: :array, value: list}, rest}

      <<current::utf8>> == "," and list == [] ->
        IO.puts("FLAG B")
        :error

      <<current::utf8>> in [" ", "\s", ","] ->
        parse_array(rest, list)

      true ->
        {value, rest} = parse_value(content)
        parse_array(rest, list ++ [value])
    end
  end

  defp parse_object(_, _ \\ %{})

  defp parse_object("", _) do
    IO.puts("FLAG C")
    :error
  end

  defp parse_object(content, map) do
    <<current::utf8, rest::binary>> = skip_whitespace(content)

    cond do
      <<current::utf8>> == "}" ->
        rest = skip_whitespace(rest)
        {%{type: :object, value: map}, rest}

      <<current::utf8>> == "," and map == %{} ->
        IO.puts("FLAG D")
        :error

      <<current::utf8>> in [" ", "\s", ","] ->
        parse_object(rest, map)

      true ->
        case parse_kv(content) do
          {{key, value}, rest} ->
            parse_object(rest, map |> Map.put(key, value))

          _ ->
            IO.puts("FLAG E")
            :error
        end
    end
  end

  defp parse_kv(content) do
    content = skip_whitespace(content)

    case parse_key(content) do
      {%{type: :string, subtype: _, value: key}, rest} ->
        <<current::utf8, rest::binary>> = skip_whitespace(rest)

        case <<current::utf8>> do
          ":" ->
            {value, rest} = parse_value(rest)
            rest = skip_whitespace(rest)
            {{key, value}, rest}

          _ ->
            IO.puts("FLAG F")
            :error
        end

      _ ->
        IO.puts("FLAG G")
        :error
    end
  end

  defp parse_key(content) do
    <<current::utf8, rest::binary>> = skip_whitespace(content)

    case <<current::utf8>> do
      "\"" ->
        parse_string(rest, :single)

      _ ->
        parse_generic(content)
    end
  end

  defp parse_string(_, _, _ \\ "")

  defp parse_string(<<"\\">>, _, _) do
    IO.puts("FLAG H")
    :error
  end

  defp parse_string(<<"\\", "\"", rest::binary>>, :multi, storage) do
    parse_string(rest, :multi, "#{storage}\\\"")
  end

  defp parse_string(<<"\\", "\"", rest::binary>>, :single, storage) do
    parse_string(rest, :single, "#{storage}\"")
  end

  defp parse_string(<<"`", rest::binary>>, :multi, storage) do
    {%{type: :string, subtype: :multi, value: storage}, rest}
  end

  defp parse_string(<<"\"", rest::binary>>, :single, storage) do
    {%{type: :string, subtype: :single, value: storage}, rest}
  end

  defp parse_string(<<"\\", escaped::utf8, rest::binary>>, subtype, storage) do
    case <<escaped::utf8>> do
      "n" ->
        parse_string(rest, subtype, "#{storage}\n")

      "b" ->
        parse_string(rest, subtype, "#{storage}\b")

      "f" ->
        parse_string(rest, subtype, "#{storage}\f")

      "t" ->
        parse_string(rest, subtype, "#{storage}\t")

      "r" ->
        parse_string(rest, subtype, "#{storage}\r")

      "\\" ->
        parse_string(rest, subtype, "#{storage}\\")

      "u" ->
        parse_hex(rest, subtype, storage)

      _ ->
        :error
    end
  end

  defp parse_string(<<32::utf8, rest::binary>>, :single, storage) do
    parse_string(rest, :single, "#{storage} ")
  end

  defp parse_string(<<current::utf8, rest::binary>>, :single, _storage)
       when <<current::utf8>> in @whitespace do
    IO.puts("FLAG I")
    :error
  end

  defp parse_string(<<current::utf8, rest::binary>>, subtype, storage) do
    parse_string(rest, subtype, "#{storage}#{<<current::utf8>>}")
  end

  defp parse_generic(_, _ \\ "")

  defp parse_generic(<<current::utf8>>, storage) do
    {handle_generic("#{storage}#{<<current::utf8>>}"), ""}
  end

  defp parse_generic(<<current::utf8, _::binary>> = content, storage)
       when <<current::utf8>> in [",", "}", "]", ":"] do
    {handle_generic(storage), content}
  end

  defp parse_generic(<<current::utf8, rest::binary>>, storage)
       when <<current::utf8>> in @whitespace do
    {handle_generic(storage), rest}
  end

  defp parse_generic(<<current::utf8, _::binary>> = content, storage)
       when <<current::utf8>> in @invalid_for_generics do
    :error
  end

  defp parse_generic(<<current::utf8, rest::binary>>, storage) do
    parse_generic(rest, "#{storage}#{<<current::utf8>>}")
  end

  defp parse_hex("", parent_type, storage) do
    IO.puts("FLAG K")
    :error
  end

  defp parse_hex(content, parent_type, storage) do
    <<first::utf8, second::utf8, third::utf8, fourth::utf8, rest::binary>> = content

    case Integer.parse(
           "#{<<first::utf8>>}#{<<second::utf8>>}#{<<third::utf8>>}#{<<fourth::utf8>>}",
           16
         ) do
      {code, ""} ->
        parse_string(rest, parent_type, "#{storage}#{<<code::utf8>>}")

      _ ->
        IO.puts("FLAG L")
        :error
    end
  end

  defp parse_comments(content, comments \\ []) do
    case content do
      <<"//", rest::binary>> ->
        {comment, rest} = parse_comment(rest, :single)
        parse_comments(rest, comments ++ [comment])

      <<"/*", rest::binary>> ->
        {comment, rest} = parse_comment(rest, :multi)
        parse_comments(rest, comments ++ [comment])

      _ ->
        comments
    end
  end

  defp parse_comment(_, _ \\ "")

  defp parse_comment(<<"\n", rest::binary>>, :single, storage) do
    {%{type: :comment, subtype: :single, value: storage}, rest}
  end

  defp parse_comment(<<"*/", rest::binary>>, :multi, storage) do
    {%{type: :comment, subtype: :multi, value: storage}, rest}
  end

  defp parse_comment(<<current::utf8, rest::binary>>, subtype, storage) do
    parse_comment(rest, subtype, "#{storage}#{<<current::utf8>>}")
  end

  defp skip_whitespace("") do
    ""
  end

  defp skip_whitespace(<<current::utf8, rest::binary>> = content) do
    cond do
      <<current::utf8>> in @whitespace ->
        skip_whitespace(rest)

      true ->
        content
    end
  end

  defp handle_generic("true") do
    %{type: :boolean, value: true}
  end

  defp handle_generic("false") do
    %{type: :boolean, value: false}
  end

  defp handle_generic("null") do
    %{type: nil}
  end

  defp handle_generic(generic) when is_binary(generic) do
    case Integer.parse(generic) do
      {integer, ""} ->
        %{type: :number, subtype: :integer, value: integer}

      _ ->
        try do
          Float.parse(generic)
        rescue
          ArgumentError ->
            %{type: :string, subtype: :free, value: generic}
        else
          {float, ""} ->
            %{type: :number, subtype: :float, value: float}

          _ ->
            %{type: :string, subtype: :free, value: generic}
        end
    end
  end
end
