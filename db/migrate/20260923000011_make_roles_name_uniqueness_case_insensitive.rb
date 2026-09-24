# frozen_string_literal: true

class MakeRolesNameUniquenessCaseInsensitive < ActiveRecord::Migration[8.0]
  def up
    remove_index :roles, %i[account_id name]
    execute 'CREATE UNIQUE INDEX index_roles_on_account_id_and_lower_name ON roles (account_id, lower(name))'
  end

  def down
    execute 'DROP INDEX index_roles_on_account_id_and_lower_name'
    add_index :roles, %i[account_id name], unique: true
  end
end
