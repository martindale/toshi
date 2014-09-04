Sequel.migration do
  change do
    create_table(:addresses) do
      primary_key :id
      column :address, :text
      column :hash160, :text
      column :compressed, :boolean
      column :label, :text
      column :address_type, :smallint
      column :created_at, :timestamp, default: Sequel::CURRENT_TIMESTAMP, null: false

      index [:address], unique: true
    end

    create_table(:blocks) do
      primary_key :id
      column :hsh, :text, null: false
      column :height, :bigint
      column :prev_block, :text
      column :mrkl_root, :text
      column :time, :bigint
      column :bits, :bigint
      column :nonce, :bigint
      column :ver, :bigint
      column :branch, :smallint
      column :size, :integer
      column :work, :bytea
      column :fees, :bigint
      column :total_in_value, :bigint
      column :total_out_value, :bigint
      column :transactions_count, :integer
      column :created_at, :timestamp, default: Sequel::CURRENT_TIMESTAMP, null: false

      index [:branch]
      index [:height]
      index [:hsh], unique: true
      index [:prev_block]
    end

    create_table(:inputs) do
      primary_key :id
      column :hsh, :text, null: false
      column :prev_out, :text, null: false
      column :index, :bigint, null: false
      column :script, :bytea
      column :sequence, :bytea
      column :position, :integer

      index [:hsh, :position]
      index [:prev_out, :index]
    end

    create_table(:outputs) do
      primary_key :id
      column :hsh, :text, null: false
      column :amount, :bigint, null: false
      column :script, :bytea, null: false
      column :position, :bigint
      column :spent, :boolean, default: false
      column :branch, :smallint
      column :type, :text

      index [:branch]
      index [:hsh, :position]
      index [:position]
      index [:spent]
    end

    create_table(:peers) do
      primary_key :id
      column :hostname, :text
      column :ip, :text
      column :port, :bigint
      column :services, :bigint
      column :last_seen, :timestamp
      column :connected, :boolean, default: false
      column :favorite, :boolean, default: false
      column :worker_name, :text
      column :connection_id, :text

      index [:connected]
      index [:favorite]
      index [:ip], unique: true
      index [:last_seen]
    end

    create_table(:raw_blocks) do
      primary_key :id
      column :hsh, :text, null: false
      column :payload, :bytea

      index [:hsh], unique: true
    end

    create_table(:raw_transactions) do
      primary_key :id
      column :hsh, :text, null: false
      column :payload, :bytea

      index [:hsh], unique: true
    end

    create_table(:transactions) do
      primary_key :id
      column :hsh, :text, null: false
      column :ver, :bigint
      column :lock_time, :bigint
      column :size, :integer
      column :pool, :smallint, null: false
      column :fee, :bigint
      column :total_in_value, :bigint
      column :total_out_value, :bigint
      column :inputs_count, :integer
      column :outputs_count, :integer
      column :height, :bigint, default: 0, null: false
      column :created_at, :timestamp, default: Sequel::CURRENT_TIMESTAMP, null: false

      index [:hsh], unique: true
      index [:pool]
    end

    create_table(:unconfirmed_addresses) do
      primary_key :id
      column :address, :text
      column :hash160, :text
      column :compressed, :boolean
      column :balance, :bigint
      column :label, :text
      column :address_type, :smallint
      column :created_at, :timestamp, default: Sequel::CURRENT_TIMESTAMP, null: false

      index [:address], unique: true
      index [:address_type]
    end

    create_table(:unconfirmed_inputs) do
      primary_key :id
      column :hsh, :text, null: false
      column :prev_out, :text, null: false
      column :index, :bigint, null: false
      column :script, :bytea
      column :sequence, :bytea
      column :position, :integer

      index [:hsh, :position]
      index [:position]
      index [:prev_out, :index]
    end

    create_table(:unconfirmed_outputs) do
      primary_key :id
      column :hsh, :text, null: false
      column :amount, :bigint, null: false
      column :script, :bytea, null: false
      column :position, :bigint
      column :spent, :boolean, default: false
      column :type, :text

      index [:hsh, :position]
      index [:position]
      index [:spent]
      index [:type]
    end

    create_table(:unconfirmed_raw_transactions) do
      primary_key :id
      column :hsh, :text, null: false
      column :payload, :bytea

      index [:hsh], unique: true
    end

    create_table(:unconfirmed_transactions) do
      primary_key :id
      column :hsh, :text, null: false
      column :ver, :bigint
      column :lock_time, :bigint
      column :size, :integer
      column :fee, :bigint
      column :pool, :smallint
      column :total_in_value, :bigint
      column :total_out_value, :bigint
      column :inputs_count, :integer
      column :outputs_count, :integer
      column :created_at, :timestamp, default: Sequel::CURRENT_TIMESTAMP, null: false

      index [:hsh], unique: true
    end

    create_table(:address_ledger_entries) do
      primary_key :id
      foreign_key :address_id, :addresses, type: :bigint
      foreign_key :transaction_id, :transactions, type: :bigint
      foreign_key :input_id, :inputs, type: :bigint
      foreign_key :output_id, :outputs, type: :bigint
      column :amount, :bigint, null: false

      index [:address_id]
      index [:transaction_id]
    end

    create_table(:addresses_outputs) do
      primary_key :id
      foreign_key :address_id, :addresses
      foreign_key :output_id, :outputs, null: false

      index [:address_id, :output_id]
      index [:output_id, :address_id]
    end

    create_table(:blocks_transactions) do
      foreign_key :block_id, :blocks, null: false
      foreign_key :transaction_id, :transactions, null: false
      column :position, :integer

      primary_key [:block_id, :transaction_id]

      index [:transaction_id, :block_id]
    end

    create_table(:unconfirmed_addresses_outputs) do
      foreign_key :address_id, :unconfirmed_addresses, null: false
      foreign_key :output_id, :unconfirmed_outputs, null: false

      primary_key [:address_id, :output_id]

      index [:output_id, :address_id]
    end

    create_table(:unconfirmed_ledger_entries) do
      primary_key :id
      foreign_key :address_id, :unconfirmed_addresses, type: :bigint
      foreign_key :transaction_id, :unconfirmed_transactions, type: :bigint
      foreign_key :input_id, :unconfirmed_inputs, type: :bigint
      foreign_key :output_id, :unconfirmed_outputs, type: :bigint
      column :amount, :bigint, null: false

      index [:address_id]
      index [:transaction_id]
    end

    create_table(:unspent_outputs) do
      primary_key :id
      foreign_key :output_id, :outputs, type: :bigint, null: false
      column :amount, :bigint, null: false
      foreign_key :address_id, :addresses, type: :bigint

      index [:address_id]
      index [:amount]
      index [:output_id]
    end
  end
end
