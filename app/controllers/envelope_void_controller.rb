# frozen_string_literal: true

class EnvelopeVoidController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def create
    @envelope.submission.update!(archived_at: Time.current)

    WebhookUrls.enqueue_events(@envelope.submission, 'submission.archived')

    @envelope.update!(status: :voided)

    redirect_to transaction_path(@transaction), notice: 'Envelope has been voided.'
  end
end
