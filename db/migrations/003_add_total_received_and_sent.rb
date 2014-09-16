Sequel.migration do
  change do
    alter_table(:addresses) do
      # these are too expensive to compute on the fly for popular addresses
      add_column :total_received, :bigint, default: 0
      add_column :total_sent, :bigint, default: 0
    end
  end
end
