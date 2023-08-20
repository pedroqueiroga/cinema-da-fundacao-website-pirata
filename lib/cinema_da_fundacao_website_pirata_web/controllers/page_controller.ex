defmodule CinemaDaFundacaoWebsitePirataWeb.PageController do
  use CinemaDaFundacaoWebsitePirataWeb, :controller

  @supported_cinemas ["porto", "derby"]

  def reverse(l) do
    case l do
      [] -> []
      [x] -> [x]
      [x|xs] -> reverse(xs) ++ [x]
    end
  end

  def normalize_str(str, strong \\ false) do
    String.downcase(str)
    |> String.replace(~r/[[:punct:]]/u, " ")
    |> String.replace(~r/ +/, if strong == true do "" else " " end)
    |> String.trim
  end

  def candidates(movie_list, str, strong_normalize \\ false) do
    str = normalize_str(str, strong_normalize)
    Enum.reduce(movie_list, [], fn movie, acc ->
      down_cased_movie = normalize_str(movie, strong_normalize)
      if String.starts_with?(down_cased_movie, str) do
        [%{movie: movie, jaro: String.jaro_distance(down_cased_movie, str)} | acc]
      else
        acc
      end
    end)
  end

  def most_powerful_candidate(candidate_list) do
    case candidate_list do
      [] -> nil
      [candidate] -> Map.merge(candidate, %{unique: true})
      [_head|_tail] ->
        candidate_list
        |> Enum.sort_by(fn %{movie: jaro} -> jaro end, :desc)
        |> Enum.at(0)
    end
  end

  def candidates_diff(candidates1, candidates2) do
    most_powerful_candidate1 = most_powerful_candidate(candidates1)
    most_powerful_candidate2 = most_powerful_candidate(candidates2)
    diff = case {most_powerful_candidate1, most_powerful_candidate2} do
             {nil, nil} -> 0
             {nil, v} -> v.jaro
             {v, nil} -> -(v.jaro)
             {v1, v2} -> v2.jaro - v1.jaro
    end
    if diff > 0 do
      {diff, most_powerful_candidate2}
    else
      {diff, most_powerful_candidate1}
    end
  end

  def group_str(movie_list, v, acc) do
    # tokens may depend on known options (movie list)
    case reverse(acc) do
      [] -> [v]
      [feet] ->
        {feet_candidates, considered_value_candidates} = {candidates(movie_list, feet), candidates(movie_list, "#{feet} #{v}")}
        feet_candidates = case feet_candidates do
                            [] -> candidates(movie_list, feet, true)
                            _ -> feet_candidates
                          end
        considered_value_candidates = case considered_value_candidates do
                                        [] -> candidates(movie_list, "#{feet} #{v}", true)
                                        _ -> considered_value_candidates
                                      end

        {c_diff, most_powerful_candidate} = candidates_diff(feet_candidates, considered_value_candidates)
        cond do
          c_diff < 0 or (c_diff == nil and most_powerful_candidate.jaro > 0.5) ->
            [most_powerful_candidate.movie | [v]]
          c_diff >= 0 ->
            if most_powerful_candidate[:unique] == true do
              [most_powerful_candidate.movie]
            else
              ["#{feet} #{v}"]
            end
          nil ->
            []
        end
      [feet|body] ->
        {feet_candidates, considered_value_candidates} = {candidates(movie_list, feet), candidates(movie_list, "#{feet} #{v}")}
        feet_candidates = case feet_candidates do
                            [] -> candidates(movie_list, feet, true)
                            _ -> feet_candidates
                          end
        considered_value_candidates = case considered_value_candidates do
                                        [] -> candidates(movie_list, "#{feet} #{v}", true)
                                        _ -> considered_value_candidates
                                      end

        {c_diff, most_powerful_candidate} = candidates_diff(feet_candidates, considered_value_candidates)
        cond do
          c_diff < 0 or (c_diff == nil and most_powerful_candidate.jaro > 0.5) ->
            reverse([v|[most_powerful_candidate.movie|body]])
          c_diff >= 0 ->
            if most_powerful_candidate[:unique] == true do
              reverse([most_powerful_candidate.movie|body])
            else
              reverse(["#{feet} #{v}"|body])
            end
          nil ->
            reverse(body)
        end
    end
  end

  def tokenize(str, movie_list) do
    splitted = String.split(str, " ")
    if String.match?(str, ~r/^((\d\dh(\d(\d|o)m?)?) ?){6}$/) do
      splitted
    else
      grouped_tokens = Enum.reduce(splitted, [], fn v, acc -> group_str(movie_list, v, acc) end)
      last_token = List.last(grouped_tokens)
      if Enum.member?(movie_list, last_token) == false do
        case most_powerful_candidate(candidates(movie_list, last_token)) do
          nil -> grouped_tokens
          candidate -> List.replace_at(grouped_tokens, length(grouped_tokens) - 1, candidate.movie)
        end
      else
        grouped_tokens
      end
      |> Enum.filter(fn movie -> Enum.member?(movie_list, movie) end)
    end
  end

  # def image_path("porto"), do: ~p"/images/Progamacao-geral_porto.png"
  # def image_path("derby"), do: "/images/Progamacao-geral_derby.png"
  def image_path(cinema) do
    Application.app_dir(:cinema_da_fundacao_website_pirata, "priv/static/images/Progamacao-geral_#{cinema}.png")
  end

  def scan_schedule(days, movie_list, cinema) do
    TesseractOcr.read(image_path(cinema), %{lang: "por", psm: 4})
    |> String.split("\n")
    |> Enum.filter(fn v -> String.trim(v) |> String.length > 0 end)
    |> Enum.map(fn v ->
      formatted_movie_list = Enum.into(movie_list, [], fn {k,_v} -> k end)
      v
      |> tokenize(formatted_movie_list)
    end)
    |> Enum.filter(fn line -> Kernel.length(line) > 1 end)
    |> Enum.zip
    |> Enum.zip(days)
    |> Enum.reduce(%{}, fn {horario, dia}, acc ->
      horario = horario
      |> Tuple.to_list
      |> Enum.reduce([], fn time_movie, acc ->
        if String.match?(time_movie, ~r/\d\dh(\d(\d|o)m?)?/) do
          [time_movie|acc]
        else
          case acc do
            [time] ->
              [%{time: time, movie: time_movie}]
            [time|acc] ->
              [%{time: time, movie: time_movie}|acc]
            _ -> []
          end
        end
      end)
      |> reverse
      Map.merge(acc, %{dia => horario}) end)
  end

  def home(conn, params \\ %{"cinema" => "porto"}) do
    cinema = case params do
               %{"cinema" => ""} -> "derby"
               %{"cinema" => nil} -> "porto"
               %{"cinema" => cinema} -> cinema
               _ -> "porto"
             end
    # get movie list
    movie_list =
      case HTTPoison.get("https://cinemadafundacao.com.br/filmes-2/") do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, document} = Floki.parse_document(body)
          Floki.find(document, ".entry-title > a")
          |> Enum.reduce(%{}, fn {_, attrs, [innerHTML]}, acc ->
            {"href", href} = Enum.find(attrs, fn {attr_name, content} -> attr_name == "href" end)
            Map.merge(acc, %{innerHTML => href})
          end)
        {:ok, %HTTPoison.Response{status_code: 404}} ->
          IO.puts "Not found :("
        {:error, %HTTPoison.Error{reason: reason}} ->
          IO.inspect reason
      end

    days = ["QUI", "SEX", "SÁB", "DOM", "TER", "QUA"]
    schedule = scan_schedule(days, movie_list, cinema)
    row_number = 2 + length(schedule[Enum.at(days, 0)])

    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false, schedule: schedule, days: days, movie_list: movie_list, cinema: cinema, other_cinemas: Enum.filter(@supported_cinemas, fn s_c -> cinema !== s_c end), row_number: row_number)
  end
end
