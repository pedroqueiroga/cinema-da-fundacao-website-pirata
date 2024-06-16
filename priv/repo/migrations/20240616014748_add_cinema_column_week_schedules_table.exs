defmodule CinemaDaFundacaoWebsitePirata.Repo.Migrations.AddCinemaColumnWeekSchedulesTable do
  use Ecto.Migration

  def change do
    alter table("week_schedules") do
      add :cinema, :string
    end
  end
end
