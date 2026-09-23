# frozen_string_literal: true

class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.string :name, null: false
      t.integer :status, null: false, default: 0
      t.references :account, null: false, foreign_key: true, index: true
      t.references :created_by_user, null: true, foreign_key: { to_table: :users }, index: true

      t.timestamps
    end
  end
end
