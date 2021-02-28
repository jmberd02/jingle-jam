class StripeController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :webhook
  before_action :skip_stripe_checkout, only: :prep_checkout_session, if: -> { Rails.env.test? }

  def prep_checkout_session
    error "Unsupported currency" unless Currency.supported?(params[:currency])

    amount = Monetize.parse!("#{params[:currency]} #{params[:amount]}")

    error "Minimum donation #{min_donation.format} (you provided #{amount.format})" unless amount >= min_donation

    stripe_session = Stripe::Checkout::Session.create({
      payment_method_types: ["card"],
      line_items: [{
        price_data: {
          currency: params[:currency],
          product_data: {
            name: "JingleJam donation",
          },
          unit_amount: amount.cents,
        },
        quantity: 1,
      }],
      mode: "payment",
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: {
        donator_id: current_donator.id,
        message: params[:message],
      },
    })

    render json: { id: stripe_session.id }
  end

  def webhook
    begin
      sig_header = request.env['HTTP_STRIPE_SIGNATURE']
      payload = request.body.read
      event = Stripe::Webhook.construct_event(payload, sig_header, ENV["STRIPE_WEBHOOK_SECRET_KEY"])

      handle_event(event.to_hash.deep_symbolize_keys)

      head :ok
    rescue JSON::ParserError
      head :unprocessable_entity
    rescue Stripe::SignatureVerificationError
      head :unauthorized
    end
  end

private

  def min_donation
    @min_donation ||= Money.new(200, params[:currency])
  end

  def handle_completed_checkout(checkout_session)
    session[:donator_id] = checkout_session.dig(:metadata, :donator_id)

    donation = Donation.new(
      amount: Money.new(checkout_session[:amount_total], checkout_session[:currency]),
      message: checkout_session.dig(:metadata, :message),
      donator: current_donator,
      stripe_checkout_session_id: checkout_session[:id],
    )

    if checkout_session[:payment_status] == "paid"
      donation.confirm_payment!
      BundleCheckJob.perform_later(donation.donator_id)
      # TODO: Notify user
      # TODO: Notify webhooks
    else
      donation.save!
    end

    if current_donator.persisted? && current_donator.previously_new_record?
      session[:donator_id] = current_donator.id
    end
  end

  def handle_async_payment(checkout_session, success: true)
    return unless (donation = Donation.find_by(stripe_checkout_session_id: checkout_session[:id]))

    if success
      donation.confirm_payment!
      BundleCheckJob.perform_later(donation.donator_id)
      # TODO: Notify webhooks
    else
      donation.cancel!
    end

    # TODO: Notify user
  end

  def handle_event(event)
    event_data = event.dig(:data, :object)

    case event[:type]
    when "checkout.session.completed"
      handle_completed_checkout(event_data)
    when "checkout.session.async_payment_succeeded"
      handle_async_payment(event_data)
    when "checkout.session.async_payment_failed"
      handle_async_payment(event_data, success: false)
    end
  end

  def skip_stripe_checkout
    handle_event(fake_stripe_checkout_event)

    redirect_to success_url
  end

  def fake_stripe_checkout_event
    amount = Monetize.parse!("#{params[:currency]} #{params[:amount]}")

    {
      type: "checkout.session.completed",
      data: {
        # https://stripe.com/docs/api/checkout/sessions/object
        object: {
          id: "cs_test_yg1S98CW7T013zdCnGV3YtShqwFlfZgZPIFtsrFFSoZhG0uC7n2rtdRG",
          object: "checkout.session",
          allow_promotion_codes: nil,
          amount_subtotal: nil,
          amount_total: amount.cents,
          billing_address_collection: nil,
          cancel_url: cancel_url,
          client_reference_id: nil,
          currency: nil,
          customer: nil,
          customer_details: nil,
          customer_email: nil,
          livemode: false,
          line_items: [{
            price_data: {
              currency: params[:currency],
              product_data: {
                name: "JingleJam donation",
              },
              unit_amount: amount.cents,
            },
            quantity: 1,
          }],
          locale: nil,
          metadata: {
            donator_id: current_donator.id,
            message: params[:message],
          },
          mode: "payment",
          payment_intent: "pi_1EUmyo2x6R10KRrhUuJXu9m0",
          payment_method_types: ["card"],
          payment_status: "paid",
          setup_intent: nil,
          shipping: nil,
          shipping_address_collection: nil,
          submit_type: nil,
          subscription: nil,
          success_url: success_url,
          total_details: nil,
        }
      }
    }
  end

  def success_url
    donations_url(status: "success")
  end

  def cancel_url
    donations_url(status: "cancelled")
  end
end