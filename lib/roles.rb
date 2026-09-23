# frozen_string_literal: true

module Roles
  module_function

  def find_or_create_by_name(account, name)
    return nil if name.blank?

    account.roles.where('lower(name) = ?', name.to_s.downcase).first ||
      account.roles.create!(name: name.to_s.strip)
  end
end
