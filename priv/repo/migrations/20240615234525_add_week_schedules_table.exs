defmodule CinemaDaFundacaoWebsitePirata.Repo.Migrations.AddWeekSchedulesTable do
  use Ecto.Migration

  def change do
    create table("week_schedules") do
      add :week_schedule, :text
      add :week_movie_list, :text

      timestamps()
    end
  end
end
