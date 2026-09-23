# frozen_string_literal: true

class CreateTransactionParties < ActiveRecord::Migration[8.0]
  def change
    create_table :transaction_parties do |t|
      t.references :transaction, null: false, foreign_key: true, index: true
      t.references :role, null: false, foreign_key: true, index: true

      t.integer :party_type, null: false, default: 0

      t.string :first_name
      t.string :last_name
      t.string :company_name
      t.string :signer_first_name
      t.string :signer_last_name
      t.string :signer_title

      t.string :email
      t.string :phone

      t.string :address_street
      t.string :address_city
      t.string :address_state
      t.string :address_zip

      t.string :mailing_address_street
      t.string :mailing_address_city
      t.string :mailing_address_state
      t.string :mailing_address_zip

      t.timestamps
    end
  end
end
