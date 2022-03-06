defmodule JSONC.Tokenizer do
  @moduledoc false

  use Agent

  @whitespace ["\v", "\f", "\r", "\n", "\s", "\t", "\b"]

  @invalid_characters_for_generics [
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

  def start_tokenizer(content) when is_binary(content) do
    case String.valid?(content) do
      true ->
        Agent.start_link(fn -> {content, cursor: {1, 0}, token: nil} end, name: {:global, self()})

      false ->
        {:error, "invalid input"}
    end
  end

  def stop_tokenizer do
    Agent.stop({:global, self()})
  end

  def next do
    Agent.get_and_update({:global, self()}, __MODULE__, :next, [])
  end

  def peek do
    case Agent.get({:global, self()}, __MODULE__, :next, []) do
      {token, _} -> token
    end
  end

  def next(_content, _state \\ {:start, ""})

  def next({"", cursor: cursor, token: _token}, {:start, ""}) do
    {:done, {"", cursor: cursor, token: nil}}
  end

  def next({"", cursor: {line, column} = cursor, token: _token}, {:generic, generic}) do
    {{handle_generic(generic), line, column}, {"", cursor: cursor, token: nil}}
  end

  def next({"", cursor: {line, column}, token: _token}, {:string, _subtype, _storage}) do
    {{:error, "unexpected end of input"}, {"", cursor: {line, column}, token: nil}}
  end

  def next(
        {<<current::utf8, rest::binary>>, cursor: {line, column}, token: token},
        {:start, _} = state
      ) do
    case <<current::utf8>> do
      "/" when rest == "" ->
        {{:error, "unexpected end of input"}, {rest, cursor: {line, column}, token: nil}}

      "/" ->
        <<peeked::utf8, peeked_rest::binary>> = rest

        case <<peeked::utf8>> do
          "/" ->
            next(
              {peeked_rest, cursor: {line, column + 2}, token: {line, column}},
              {:comment, :single, ""}
            )

          "*" ->
            next(
              {peeked_rest, cursor: {line, column + 2}, token: {line, column}},
              {:comment, :multi, ""}
            )

          _ ->
            {{:error,
              "unexpected character `#{<<peeked::utf8>>}` at line #{line} column #{column}"},
             {rest, cursor: {line, column}, token: nil}}
        end

      "{" ->
        {{{:delimiter, {:brace, :open}}, line, column},
         {rest, cursor: {line, column + 1}, token: nil}}

      "}" ->
        {{{:delimiter, {:brace, :close}}, line, column},
         {rest, cursor: {line, column + 1}, token: nil}}

      "[" ->
        {{{:delimiter, {:bracket, :open}}, line, column},
         {rest, cursor: {line, column + 1}, token: nil}}

      "]" ->
        {{{:delimiter, {:bracket, :close}}, line, column},
         {rest, cursor: {line, column + 1}, token: nil}}

      "," ->
        {{{:delimiter, :comma}, line, column}, {rest, cursor: {line, column + 1}, token: nil}}

      ":" ->
        {{{:delimiter, :colon}, line, column}, {rest, cursor: {line, column + 1}, token: nil}}

      "\"" ->
        next({rest, cursor: {line, column + 1}, token: {line, column}}, {:string, :single, ""})

      "`" ->
        next({rest, cursor: {line, column + 1}, token: {line, column}}, {:string, :multi, ""})

      "\n" ->
        next({rest, cursor: {line + 1, 1}, token: token}, state)

      ch when ch in @whitespace ->
        next({rest, cursor: {line, column + 1}, token: token}, state)

      ch when ch in @invalid_characters_for_generics ->
        {{:error, "unexpected character `#{<<current::utf8>>}` at line #{line} column #{column}"},
         {rest, cursor: {line, column + 1}, token: nil}}

      _ ->
        next(
          {"#{<<current::utf8>>}#{rest}", cursor: {line, column}, token: {line, column}},
          {:generic, ""}
        )
    end
  end

  def next(
        {<<current::utf8, rest::binary>>, cursor: {line, column}, token: token},
        {:generic, storage}
      ) do
    case rest do
      "" ->
        {{handle_generic("#{storage}#{<<current::utf8>>}"), token |> elem(0), token |> elem(1)},
         {rest, cursor: {line, column + 1}, token: nil}}

      _ ->
        <<peeked::utf8, _peeked_rest::binary>> = rest

        cond do
          <<current::utf8>> == "\n" ->
            {{handle_generic("#{storage}"), token |> elem(0), token |> elem(1)},
             {rest, cursor: {line + 1, 1}, token: nil}}

          <<current::utf8>> in @whitespace ->
            {{handle_generic("#{storage}"), token |> elem(0), token |> elem(1)},
             {rest, cursor: {line, column + 1}, token: nil}}

          <<peeked::utf8>> == ":" ->
            {{{:key, "#{storage}#{<<current::utf8>>}"}, token |> elem(0), token |> elem(1)},
             {rest, cursor: {line, column + 1}, token: nil}}

          <<peeked::utf8>> in [",", "}", "]"] ->
            {
              {
                handle_generic("#{storage}#{<<current::utf8>>}"),
                token |> elem(0),
                token |> elem(1)
              },
              {rest, cursor: {line, column + 1}, token: nil}
            }

          <<current::utf8>> in @invalid_characters_for_generics ->
            {{:error,
              "unexpected character `#{<<current::utf8>>}` at line #{line} column #{column}"},
             {rest, cursor: {line, column + 1}, token: nil}}

          true ->
            next(
              {rest, cursor: {line, column + 1}, token: token},
              {:generic, "#{storage}#{<<current::utf8>>}"}
            )
        end
    end
  end

  def next(
        {<<current::utf8, rest::binary>>, cursor: {line, column}, token: token},
        {:string, subtype, storage}
      ) do
    case rest do
      "" ->
        {{:error, "unexpected end of input"}, {rest, cursor: {line, column}, token: nil}}

      _ ->
        <<peeked::utf8, _peeked_rest::binary>> = rest

        case <<current::utf8>> do
          "\"" when subtype == :single and <<peeked::utf8>> == ":" ->
            cond do
              String.contains?(storage, "\\") ->
                {{:error, "invalid key #{storage} at line #{line} column #{column}"},
                 {rest, cursor: {line, column}, token: nil}}

              true ->
                {{{:key, storage}, token |> elem(0), token |> elem(1)},
                 {rest, cursor: {line, column + 1}, token: nil}}
            end

          "\"" when subtype == :single ->
            {{{:string, {:single, storage}}, token |> elem(0), token |> elem(1)},
             {rest, cursor: {line, column + 1}, token: nil}}

          "`" when subtype == :multi ->
            {{{:string, {:multi, storage}}, token |> elem(0), token |> elem(1)},
             {rest, cursor: {line, column + 1}, token: nil}}

          "\\" ->
            <<peeked::utf8, peeked_rest::binary>> = rest

            case <<peeked::utf8>> do
              "n" ->
                next(
                  {peeked_rest, cursor: {line, column + 2}, token: token},
                  {:string, subtype, "#{storage}\n"}
                )

              "b" ->
                next(
                  {peeked_rest, cursor: {line, column + 2}, token: token},
                  {:string, subtype, "#{storage}\b"}
                )

              "f" ->
                next(
                  {peeked_rest, cursor: {line, column + 2}, token: token},
                  {:string, subtype, "#{storage}\f"}
                )

              "t" ->
                next(
                  {peeked_rest, cursor: {line, column + 2}, token: token},
                  {:string, subtype, "#{storage}\t"}
                )

              "r" ->
                next(
                  {peeked_rest, cursor: {line, column + 2}, token: token},
                  {:string, subtype, "#{storage}\r"}
                )

              "\\" ->
                next(
                  {peeked_rest, cursor: {line, column + 2}, token: token},
                  {:string, subtype, "#{storage}\\"}
                )

              "u" ->
                next(
                  {rest, cursor: {line, column + 2}, token: token},
                  {:hex, subtype, "#{storage}"}
                )

              "\"" when subtype == :single ->
                next(
                  {peeked_rest, cursor: {line, column + 2}, token: token},
                  {:string, subtype, "#{storage}\""}
                )

              "\"" when subtype == :multi ->
                next(
                  {peeked_rest, cursor: {line, column + 2}, token: token},
                  {:string, subtype, "#{storage}\\\""}
                )

              _ ->
                {{:error,
                  "unexpected character `#{<<peeked::utf8>>}` at line #{line} column #{column}"},
                 {rest, cursor: {line, column}, token: nil}}
            end

          "\n" when subtype == :single ->
            {{:error, "unexpected end of line at line #{line} column #{column}"},
             {rest, cursor: {line + 1, 1}, token: nil}}

          "\n" when subtype == :multi ->
            next(
              {rest, cursor: {line + 1, 1}, token: token},
              {:string, :multi, "#{storage}#{<<current::utf8>>}"}
            )

          "\s" ->
            next(
              {rest, cursor: {line, column + 1}, token: token},
              {:string, subtype, "#{storage}#{<<current::utf8>>}"}
            )

          ch when subtype == :single and ch in @whitespace ->
            {{:error,
              "unescaped whitespace character #{current} at line #{line} column #{column}"},
             {rest, cursor: {line, column}, token: nil}}

          _ ->
            next(
              {rest, cursor: {line, column + 1}, token: token},
              {:string, subtype, "#{storage}#{<<current::utf8>>}"}
            )
        end
    end
  end

  def next(
        {<<_current::utf8, rest::binary>>, cursor: {line, column}, token: token},
        {:hex, string_type, storage}
      ) do
    case rest do
      "" ->
        {{:error, "unexpected end of input"}, {rest, cursor: {line, column}, token: nil}}

      _ ->
        <<first::utf8, second::utf8, third::utf8, fourth::utf8, rest::binary>> = rest

        try do
          String.to_integer(
            "#{<<first::utf8>>}#{<<second::utf8>>}#{<<third::utf8>>}#{<<fourth::utf8>>}",
            16
          )
        rescue
          ArgumentError ->
            {{:error,
              "invalid hex sequence #{<<first::utf8>>}#{<<second::utf8>>}#{<<third::utf8>>}#{<<fourth::utf8>>}"},
             {rest, cursor: {line, column + 6}, token: nil}}
        else
          code ->
            next(
              {rest, cursor: {line, column + 6}, token: token},
              {:string, string_type, "#{storage}#{<<code::utf8>>}"}
            )
        end
    end
  end

  def next(
        {<<current::utf8, rest::binary>>, cursor: {line, column}, token: token},
        {:comment, subtype, storage}
      ) do
    case rest do
      "" ->
        {{:error, "unexpected end of input"}, {rest, cursor: {line, column + 1}, token: nil}}

      _ ->
        <<peeked::utf8, peeked_rest::binary>> = rest

        case <<current::utf8>> do
          "\n" when subtype == :single ->
            {{{:comment, {:single, storage}}, token |> elem(0), token |> elem(1)},
             {rest, cursor: {line + 1, 1}, token: nil}}

          "\n" when subtype == :multi ->
            next(
              {rest, cursor: {line + 1, 1}, token: token},
              {:comment, :multi, "#{storage}#{<<current::utf8>>}"}
            )

          _ when <<current::utf8, peeked::utf8>> == "*/" ->
            {{{:comment, {:multi, storage}}, token |> elem(0), token |> elem(1)},
             {peeked_rest, cursor: {line, column + 2}, token: nil}}

          _ ->
            next(
              {rest, cursor: {line, column + 1}, token: token},
              {:comment, subtype, "#{storage}#{<<current::utf8>>}"}
            )
        end
    end
  end

  defp handle_generic("true") do
    {:boolean, true}
  end

  defp handle_generic("false") do
    {:boolean, false}
  end

  defp handle_generic("null") do
    nil
  end

  defp handle_generic(generic) when is_binary(generic) do
    try do
      String.to_float(generic)
    rescue
      ArgumentError ->
        try do
          String.to_integer(generic)
        rescue
          ArgumentError ->
            case String.split(generic, "e") do
              [base, exponent] ->
                try do
                  {String.to_integer(base), String.to_integer(exponent)}
                rescue
                  ArgumentError ->
                    {:string, {:free, generic}}
                else
                  {base, exponent} ->
                    try do
                      String.to_float("#{base / 1}e#{exponent}")
                    rescue
                      ArgumentError ->
                        {:string, {:free, generic}}
                    else
                      float -> {:number, {:float, float}}
                    end
                end

              [generic] ->
                {:string, {:free, generic}}
            end
        else
          integer -> {:number, {:integer, integer}}
        end
    else
      float -> {:number, {:float, float}}
    end
  end
end
