Sequel.migration do
  change do
    alter_table(:unconfirmed_ledger_entries) do
      # otherwise deletes from unconfirmed_{inputs,outputs} will be painfully slow
      # see: http://www.postgresql.org/message-id/4A443367.306@lbl.gov
      add_index [:input_id]
      add_index [:output_id]
    end
  end
end
