# frozen_string_literal: true

class EnvelopeVoidController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def new; end

  def create
    reason = params.dig(:envelope, :void_reason).to_s.strip

    if reason.blank?
      flash.now[:alert] = 'A reason is required to void an envelope.'
      return render :new, status: :unprocessable_content
    end

    @envelope.submission.update!(archived_at: Time.current)

    WebhookUrls.enqueue_events(@envelope.submission, 'submission.archived')

    @envelope.update!(status: :voided, void_reason: reason)

    redirect_to transaction_path(@transaction), notice: 'Envelope has been voided.'
  end
end
