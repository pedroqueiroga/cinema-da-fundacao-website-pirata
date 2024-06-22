defmodule CinemaDaFundacaoWebsitePirataWeb.PageController do
  use CinemaDaFundacaoWebsitePirataWeb, :controller
  import Ecto.Query
  require Logger

  @supported_cinemas ["porto", "derby", "museu"]

  def reverse(l) do
    case l do
      [] -> []
      [x] -> [x]
      [x|xs] -> reverse(xs) ++ [x]
    end
  end

  def normalize_str(str, strong \\ false) do
    normalized_str = String.downcase(str)
    |> String.replace(~r/[[:punct:]]/u, " ")
    |> String.replace(~r/ +/, if strong == true do "" else " " end)
    |> String.trim
    if strong do
      Unicode.Transform.LatinAscii.transform(normalized_str)
    else
      normalized_str
    end
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

  def image_path(cinema) do
    Application.app_dir(:cinema_da_fundacao_website_pirata, "priv/static/images/Progamacao-geral_#{cinema}.png")
  end

  @hour_regex ~r/(\d\d)h(\d(?:\d|o)m?)?/

  def scan_schedule({days, dates}, movie_list, cinema) do
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
    |> Enum.zip(dates)
    |> Enum.reduce(%{}, fn {{time, day}, movie_date}, acc ->
      time_with_movie = time
      |> Tuple.to_list
      |> Enum.reduce([], fn time_movie, acc ->
        if String.match?(time_movie, @hour_regex) do
          [time_movie|acc]
        else
          [time|_] = acc
          {:ok, movie_time_struct} = get_time_struct(time)
          {:ok, movie_date_time} = get_datetime(movie_date, movie_time_struct)
          case acc do
            [time] ->
              [%{time: time, movie: time_movie, is_past: is_past_date(movie_date_time)}]
            [time|acc] ->
              [%{time: time, movie: time_movie, is_past: is_past_date(movie_date_time)}|acc]
            _ -> []
          end
        end
      end)
      |> reverse
      Map.merge(acc, %{day => time_with_movie})
    end)
  end

  def get_time_struct(nil) do nil end
  def get_time_struct(movie_time) do
    case Regex.run(@hour_regex, String.replace(movie_time, "o", "0")) do
      [_, hh, mm] -> Time.new(String.to_integer(hh), String.to_integer(mm), 00)
      [_, hh] -> Time.new(String.to_integer(hh), 00, 00)
    end
  end

  def get_time_struct!(movie_time) do
    case Regex.run(@hour_regex, String.replace(movie_time, "o", "0")) do
      [_, hh, mm] -> Time.new!(String.to_integer(hh), String.to_integer(mm), 00)
      [_, hh] -> Time.new!(String.to_integer(hh), 00, 00)
    end
  end    

  def get_datetime(date, time_struct) do
    DateTime.new(
      date,
      time_struct,
      "America/Recife"
    )
  end


  def is_past_date(nil) do nil end
  def is_past_date(date) do
    DateTime.compare(get_datetime_now(), date) != :lt
  end

  def get_datetime_now() do
    {:ok, now} = DateTime.now("America/Recife")
    now
  end

  def get_current_movie_week() do
    begin_of_week = get_datetime_now()
    |> Date.beginning_of_week(:thursday)

    Enum.concat(0..3, [5,6])
    |> Enum.map(fn v -> Date.add(begin_of_week, v) end)
  end

  def get_date_from_word(current_movie_week, word) do
    Enum.find(fn date ->
      date.day == String.to_integer(String.slice(word, 0..1))
    end)
  end

  def word_to_date(week, word) do
    Enum.find(
      week,
      fn date ->
        date.day == String.to_integer(String.slice(word, 0..1))
      end)
  end

  def columns_x_start(words) do
    current_movie_week = get_current_movie_week()
    arr = words
    |> Enum.filter(fn %{word: w} -> String.match?(w, @hour_regex) end)
    |> Enum.reduce([], fn %{x_start: x_start}, acc ->
      case acc do
        [] -> [x_start]
        _ ->
          # find index of an element that is very close to x_start
          idx = Enum.find_index(acc, fn v -> abs(x_start - v) < 20 end)
          if idx != nil do
            List.replace_at(acc, idx, div(Enum.at(acc, idx) + x_start, 2))
          else
            [x_start | acc]
          end
      end
    end)
    |> Enum.reverse
  end

  def rows_y_start(words) do
    words
    |> Enum.filter(fn %{word: w} -> String.match?(w, @hour_regex) end)
    |> Enum.reduce([], fn %{y_start: y_start}, acc ->
      case acc do
        [] -> [y_start]
        [y | ys] ->
          if abs(y - y_start) < 20 do
            [div((y + y_start), 2) | ys]
          else
            [y_start | acc]
          end
      end
    end)
    |> Enum.reverse
  end

  def tesseract_words(cinema_image_path) do
    TesseractOcr.Words.read(
      cinema_image_path,
      %{lang: "por", psm: 4, c: "preserve_interword_spaces=1"}
    )
    |> Enum.filter(fn %{confidence: confidence} ->
      confidence > 35
    end)
  end

  def get_most_recent_thursday(today_date) do
    Date.beginning_of_week(today_date, :thursday)
  end
  

  def home(conn, params \\ %{"cinema" => "porto"}) do
    cinema = case params do
               %{"cinema" => ""} -> "derby"
               %{"cinema" => nil} -> "porto"
               %{"cinema" => cinema} -> cinema
               _ -> "porto"
             end

    today_date = get_datetime_now()
    days = ["QUI", "SEX", "SÁB", "DOM", "TER", "QUA"]

    query = Ecto.Query.from(ws in CinemaDaFundacaoWebsitePirata.WeekSchedule,
      where: ws.cinema == ^cinema,
      order_by: [desc: ws.inserted_at],
      limit: 1)
    most_recent_schedule = CinemaDaFundacaoWebsitePirata.Repo.one(query)

    most_recent_thursday = get_most_recent_thursday(today_date)

    today_day_of_week = Date.day_of_week(today_date)

    other_cinemas = Enum.filter(@supported_cinemas, fn s_c ->
      cinema !== s_c
    end)

    {dates, day_month_list} = get_current_movie_week()
    |> Enum.map(fn date ->
      padded_day = date.day
      |> Integer.to_string
      |> String.pad_leading(2, "0")

      padded_month = date.month
      |> Integer.to_string
      |> String.pad_leading(2, "0")

      {date, "#{padded_day}/#{padded_month}"}
    end)
    |> Enum.unzip
    
    most_recent_schedule = case most_recent_schedule do
                             nil -> %{inserted_at: ~D[2001-01-01]}
                             _ -> most_recent_schedule
                           end

    case Date.compare(most_recent_schedule.inserted_at, most_recent_thursday) do
      :lt -> # generate new schedule and save to database
        Logger.info "generating new schedule, first attempt saving to db"  
        # get cinema filep
        schedule_png =
        case HTTPoison.get("https://cinemadafundacao.com.br/") do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, document} = Floki.parse_document(body)
          png_list = Floki.find(document, "#abas")
          |> Enum.at(1)
          |> Floki.attribute("div.lsow-tab-pane > p > img.size-full", "src")
          |> Enum.map(fn image_url ->
            case HTTPoison.get(image_url) do
              {:ok, %HTTPoison.Response{status_code: 200, body: image}} ->
                IO.inspect(image)
              {:ok, %HTTPoison.Response{status_code: 404}} ->
                IO.puts "Not found :("
              {:error, %HTTPoison.Error{reason: reason}} ->
                IO.inspect reason
            end
          end)
          cinema_list = Floki.find(document, ".lsow-tab-label > .lsow-tab-title")
          |> Enum.drop(1)
          |> Enum.map(fn el ->
            Floki.text(el)
            |> String.downcase
          end)
#          |> IO.inspect

          Enum.zip(cinema_list, png_list) |> Enum.into(%{})
#          |> IO.inspect
        {:ok, %HTTPoison.Response{status_code: 404}} ->
          IO.puts "Not found :("
        {:error, %HTTPoison.Error{reason: reason}} ->
          IO.inspect reason
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
#      |> IO.inspect(label: "movie_list")

    #schedule = scan_schedule({days, dates}, movie_list, cinema)
    #row_number = 2 + length(schedule[Enum.at(days, 0)])
    %{^cinema => cinema_image} = schedule_png

    cinema_image_path = Application.app_dir(:cinema_da_fundacao_website_pirata, "#{cinema}.png")
    File.write!(cinema_image_path, cinema_image)
    
    words = tesseract_words(cinema_image_path)
#    |> IO.inspect(label: "words")

    columns_x_start = words
    |> columns_x_start
#    |> IO.inspect(label: "columns x start")

    rows_y_start = words
    |> rows_y_start
#    |> IO.inspect(label: "rows y start")

    schedule_matrix = Enum.reduce(columns_x_start, %{}, fn column, acc_x ->
      Map.merge(acc_x, %{column => Enum.reduce(rows_y_start, %{}, fn y_start, acc_y ->
                            Map.merge(acc_y, %{y_start => %{time: nil, movie: nil}})
                          end)}
      )
    end)
#    |> IO.inspect

    new_schedule = words
    |> Enum.reduce(schedule_matrix, fn slot_candidate, acc ->
#      IO.inspect(slot_candidate)
      row_index =
        Enum.find(
          0..length(rows_y_start)-1,
          fn i ->
            yt = Enum.at(rows_y_start, i)
            yb = if i < (length(rows_y_start) - 1) do
              Enum.at(rows_y_start, i+1)
            else
              yt + abs(yt - Enum.at(rows_y_start, i-1))
            end
            slot_candidate.y_start < (yb - 15) && slot_candidate.y_start >= (yt - 15)
          end
        )
#        |> IO.inspect(label: "row")      

      col_index =
        Enum.find(
          0..length(columns_x_start)-1,
          fn i ->
            xl = Enum.at(columns_x_start, i)
            xr = if i < (length(columns_x_start) - 1) do
              Enum.at(columns_x_start, i+1)
            else
              xl + abs(xl - Enum.at(columns_x_start, i-1))
            end
            slot_candidate.x_start < (xr - 20) && slot_candidate.x_start > (xl - 20)
          end
        )
#        |> IO.inspect(label: "col")
      
      if row_index != nil && col_index != nil do
        row = Enum.at(rows_y_start, row_index)
        col = Enum.at(columns_x_start, col_index)

#        IO.inspect({row, col}, label: "best_row and best_col")
        word = slot_candidate.word
        new_item = if String.match?(word, @hour_regex) do
          Map.merge(acc[col][row], %{time: word})
        else
          movie = acc[col][row][:movie] || ""
          Map.merge(acc[col][row], %{movie: String.trim("#{movie} #{word}")})
        end
        Map.replace(acc, col,
          Map.replace(acc[col], row, new_item)
        )
      else
        acc
      end
    end)
#    |> IO.inspect
    |> Enum.zip(Enum.zip(["QUI", "SEX", "SÁB", "DOM", "TER", "QUA"], get_current_movie_week()))
#    |> IO.inspect(label: "zipped")
    |>
    Enum.reduce(
      %{},
      fn {{col, rows}, {day, date}}, acc ->
        rows =
          Enum.map(rows, fn {_, %{time: time, movie: movie}} ->
            movie_datetime =
              case get_time_struct(time) do
                {:ok, time_struct} ->
                  case get_datetime(date, time_struct) do
                    {:ok, movie_datetime} -> movie_datetime
                    _-> nil
                  end
                _ -> nil
              end
            movie = movie || "???"
            movie =
              case most_powerful_candidate(candidates(Enum.map(movie_list, fn {movie, href} -> movie end), movie, true)) do
                %{movie: candidate_movie} -> candidate_movie
                nil -> movie
              end
            time = time || "??h??"
            case movie_datetime do
              nil -> %{is_past: nil,
                      day: nil,
                      month: nil,
                      year: nil,
                      time: nil,
                      movie: nil}
              _ -> %{is_past: is_past_date(movie_datetime),
                    day: movie_datetime.day,
                    month: movie_datetime.month,
                    year: movie_datetime.year,
                    time: time,
                    movie: movie}
            end
          end)
        Map.merge(acc, %{day => rows})
      end)
      |> IO.inspect(label: "new schedule")

    row_number = 2 + length(new_schedule[Enum.at(days, 0)])

    # saving crucial information to database now
    
    CinemaDaFundacaoWebsitePirata.Repo.insert(
      %CinemaDaFundacaoWebsitePirata.WeekSchedule{
        week_schedule: Kernel.inspect(new_schedule),
        week_movie_list: Kernel.inspect(movie_list),
        cinema: cinema
      })
    
    # The home page is often custom made,
    # so skip the default app layout.
    render(
      conn,
      :home,
      layout: false,
      schedule: new_schedule,
      days: days,
      movie_list: movie_list,
      cinema: cinema,
      other_cinemas: other_cinemas,
      row_number: row_number,
      today: today_day_of_week,
      day_month_list: day_month_list
    )

      _ ->
        # * get result from database *
        Logger.info "Simply display result from database"
        Logger.info "inspect week skedul #{inspect(most_recent_schedule.week_schedule)}"
        {:ok, quoted_week_schedule} = Code.string_to_quoted(most_recent_schedule.week_schedule)
        {:ok, quoted_movie_list} = Code.string_to_quoted(most_recent_schedule.week_movie_list)
        {deserialized_most_recent_schedule,_} = Code.eval_quoted(quoted_week_schedule)
        {deserialized_movie_list, _} = Code.eval_quoted(quoted_movie_list)
        Logger.info "inspect movie list #{inspect(deserialized_movie_list)}"
        Logger.info "inspect movie schedule #{inspect(deserialized_most_recent_schedule)}"
        # update is_past information
        deserialized_most_recent_schedule =
          Enum.into(deserialized_most_recent_schedule, %{}, fn {k, hours} ->
            {k,
             Enum.map(hours, fn h ->
               case h.year do
                 nil -> h
                 _ -> %{h | is_past: is_past_date(DateTime.new!(
                             Date.new!(h.year,
                               h.month,
                               h.day),
                             get_time_struct!(h.time), "America/Recife"
                             ))}
               end
             end)
            }
          end)
      row_number = 2 + length(deserialized_most_recent_schedule[Enum.at(days, 0)])
      render(
        conn,
        :home,
        layout: false,
        schedule: deserialized_most_recent_schedule,
        days: days,
        movie_list: deserialized_movie_list,
        cinema: most_recent_schedule.cinema,
        other_cinemas: other_cinemas,
        row_number: row_number,
        today: today_day_of_week,
        day_month_list: day_month_list
      )
    end
  end
end
