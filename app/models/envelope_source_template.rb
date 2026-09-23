# frozen_string_literal: true

class EnvelopeSourceTemplate < ApplicationRecord
  belongs_to :envelope
  belongs_to :source_template, class_name: 'Template'
end
