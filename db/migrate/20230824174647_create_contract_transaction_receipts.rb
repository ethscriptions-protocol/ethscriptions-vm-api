class CreateContractTransactionReceipts < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_transaction_receipts, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.string :caller, null: false
      t.integer :status, null: false
      t.string :function_name
      t.jsonb :function_args, default: {}, null: false
      t.jsonb :logs, default: [], null: false
      t.bigint :block_timestamp, null: false
      t.string :error_message
      t.string :contract_address
      t.bigint :block_number, null: false
      t.bigint :transaction_index, null: false
      t.string :block_blockhash, null: false
      t.jsonb :return_value
      t.integer :runtime_ms, null: false
      t.string :call_type, null: false
      t.decimal :gas_price
      t.decimal :gas_used
      t.decimal :transaction_fee
    
      t.index [:block_number, :transaction_index], unique: true, name: :index_contract_tx_receipts_on_block_number_and_tx_index
      t.index :contract_address
      t.index :transaction_hash, unique: true
    
      t.check_constraint "contract_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "caller ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
    
      t.foreign_key :ethscriptions, column: :transaction_hash, primary_key: :ethscription_id, on_delete: :cascade
    
      t.timestamps
    end    
  end
end
