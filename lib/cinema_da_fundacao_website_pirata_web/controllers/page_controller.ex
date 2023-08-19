defmodule CinemaDaFundacaoWebsitePirataWeb.PageController do
  use CinemaDaFundacaoWebsitePirataWeb, :controller

  def reverse(l) do
    case l do
      [x|xs] -> reverse(xs) ++ [x]
      _ -> l
    end
  end

  def group_str(v, acc) do
    case reverse(acc) do
      [] -> [v]
      [feet] ->
        if String.length("#{feet} #{v}") < 11 do
          ["#{feet} #{v}"]
        else
          acc ++ [v]
        end
      [feet|body] ->
        if String.length("#{feet} #{v}") < 11 do
          reverse(["#{feet} #{v}"] ++ body)
        else
          acc ++ [v]
        end
    end
  end
  
  def home(conn, _params) do
    TesseractOcr.read("/home/pedro/Downloads/Progamacao-geral_derby.png", %{lang: "por", psm: 1})
    |> String.split("\n")
    |> Enum.map(fn v -> v
      |> IO.inspect
      |> String.split(" ")
      |> IO.inspect
      |> Enum.reduce([], fn v, acc -> group_str(v, acc) end)
    end)
    |> IO.inspect
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end
end
