Sequel.migration do
  change do
    create_table(:spending_inputs) do
      primary_key :id
      foreign_key :input_id, :inputs, null: false
      foreign_key :output_id, :outputs, null: false

      index [:input_id]
      index [:output_id]
    end
  end
end
