defmodule JSONC do
  @moduledoc """
  This is a package for decoding [jsonc](https://komkom.github.io/jsonc-playground) documents and also transcoding them to json.
  I'm also working on it to add a formatter.

  jsonc is a superset of json, which means any json document is also a jsonc document but the reverse is not true.
  So you can use this package to decode json documents too.

  jsonc allows you to have single-line and multi-line comments in your documents using `//` and `/* */`. these comments can be anywhere.

  you can also have multi-line strings that don't need escaping using `` ` `` (backtick).
  also, strings and object keys may be unquoted. but any unquoated string that can be intrepreted as a number(whether integer or float), will be treated as such.
  you also don't need to use commas for separating key-value pairs in objets or elements in arrays, whitespace is enough.

  This is an example of a valid jsonc document:

  ```
  // a valid jsonc document
  {
    /* you can have
       multi-line comments
    */
    key1 /* object keys can be unquoted */ : value // you don't need a comma here
    key2: [ 25.23e-5 74 unquoated_string ]
    key3: `this
            is a
            multi-line string`,
    "regular_key": "regular_string"
  }
  ```

  I should say that right now, the performance for large documents is not acceptable, so use this package only when
  human-readability is more important than performance, like using a jsonc file for specifying environmental variables
  for your app (for example with [enux](https://hex.pm/packages/enux)).
  but I'll definitely keep working on optimising the parser or maybe writing a new parser if needed.

  ## Installation

  ```
  defp deps do
    [
      {:jsonc, "~> 0.7.0"}
    ]
  end
  ```

  ## Usage

  ```
  iex(1)> JSONC.decode!(~s(// language information \\n { name: elixir github_stars: 19.8e3 forks: 2.8e3 creator: "José Valim" 😔 : 😃 }))
  %{
    "creator" => "José Valim",
    "forks" => 2.8e3,
    "github_stars" => 1.98e4,
    "name" => "elixir",
    "😔" => "😃"
  }

  iex(2)> JSONC.transcode!(~s(// language information \\n { name: elixir github_stars: 19.8e3 forks: 2.8e3 creator: "José Valim" 😔 : 😃 }))
  "{\\n    \\"name\\": \"elixir\\",\\n    \\"github_stars\\": 1.98e4,\\n    \\"forks\\": 2.8e3,\\n    \\"creator\": \\"José Valim\\"\\n    \"😔\": \"😃\"\\n}"
  ```
  """

  @doc delegate_to: {JSONC.Decoder, :decode!, 1}
  defdelegate decode!(content), to: JSONC.Decoder
  @doc delegate_to: {JSONC.Decoder, :decode, 1}
  defdelegate decode(content), to: JSONC.Decoder

  @doc delegate_to: {JSONC.Transcoder, :transcode!, 1}
  defdelegate transcode!(content), to: JSONC.Transcoder
  @doc delegate_to: {JSONC.Transcoder, :transcode, 1}
  defdelegate transcode(content), to: JSONC.Transcoder
end
