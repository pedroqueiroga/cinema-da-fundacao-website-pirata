defmodule CinemaDaFundacaoWebsitePirata.WeekSchedule do
  use Ecto.Schema

  schema "week_schedules" do
    field :week_schedule, :string # to refine
    field :week_movie_list, :string
    field :cinema, :string
    
    timestamps()
  end

end
