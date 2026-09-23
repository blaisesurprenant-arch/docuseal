# frozen_string_literal: true

class CreateRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :roles do |t|
      t.string :name, null: false
      t.references :account, null: false, foreign_key: true, index: true

      t.timestamps
    end

    add_index :roles, %i[account_id name], unique: true
  end
end
