Sequel.migration do
  change do
    alter_table(:unconfirmed_ledger_entries) do
      # otherwise deletes from unconfirmed_{inputs,outputs} will be painfully slow
      add_index [:input_id]
      add_index [:output_id]
    end
  end
end
