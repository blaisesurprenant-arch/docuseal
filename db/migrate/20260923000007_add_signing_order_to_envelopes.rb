# frozen_string_literal: true

class AddSigningOrderToEnvelopes < ActiveRecord::Migration[8.0]
  def change
    add_column :envelopes, :signing_order, :integer, null: false, default: 0
  end
end
