require 'sinatra'
require 'endpoint_base'
require 'shipping_easy'
require 'sinatra/logger'

module ShippingeasyIntegration
  class Server < EndpointBase::Sinatra::Base
    logger filename: "log/shipping_easy_integrator_#{settings.environment}.log",
           level: :trace

    before ['/cancel_order', '/create_order'] do
      logger.info "Config=#{@config}"
      logger.info "Payload=#{@payload}"

      ShippingEasy.configure do |config|
        config.api_key = @config['api_key']
        config.api_secret = @config['api_secret']
      end
    end

    post '/order_callback' do
      logger.info "Config=#{@config}"
      logger.info "Payload=#{@payload}"

      orders_from_payload = @payload['shipment']['orders']
      orders_from_payload.each do |order_payload|
        add_object :order,  id: order_payload['external_order_identifier'],
                            tracking_number: @payload['shipment']['tracking_number'],
                            shipment_cost: @payload['shipment']['shipment_cost']
      end
      result 200, 'Order from callback'
    end

    post '/update_order' do
      begin
        order = ShippingEasy::Resources::Order.find(id: @payload[:shipping_easy][:order][:sync_id])

        ShippingEasy::Resources::Cancellation
          .create(store_api_key: @config['store_api_key'],
                  external_order_identifier: \
          @payload[:shipping_easy][:order][:external_order_identifier])
        new_identifier = modify_indentifier(order['order']['external_order_identifier'])
        @payload[:shipping_easy][:order][:external_order_identifier] = new_identifier
        new_order = ShippingEasy::Resources::Order
                    .create(store_api_key: @config['store_api_key'],
                            payload: @payload[:shipping_easy])
        # response part
        add_object :order, id: demodify_identyfier(new_order['order']['external_order_identifier']),
                           sync_id: new_order['order']['id'], sync_type: 'shipping_easy'
        result 200, 'Order with is updated from Shipping Easy'
      rescue => e
        logger.error e.cause
        logger.error e.backtrace.join("\n")
        result 500, e.message
      end
    end

    post '/cancel_order' do
      begin
        response = ShippingEasy::Resources::Cancellation
                   .create(store_api_key: @config['store_api_key'],
                           external_order_identifier: \
                             @payload[:shipping_easy][:order][:external_order_identifier])

        logger.info "Response from Shipping Easy = #{response}"
        result 200, 'Order with is canceled from Shipping Easy.'
      rescue => e
        logger.error e.cause
        logger.error e.backtrace.join("\n")
        result 500, e.message
      end
    end

    post '/create_order' do
      begin
        new_order = ShippingEasy::Resources::Order
                    .create(store_api_key: @config['store_api_key'],
                            payload: @payload[:shipping_easy])

        add_object :order, id: demodify_identyfier(new_order['order']['external_order_identifier']),
                           sync_id: new_order['order']['id'], sync_type: 'shipping_easy'

        logger.info "Create order response #{new_order}"

        result 200, 'Order with is added to Shipping Easy.'
      rescue => e
        logger.error e.cause
        logger.error e.backtrace.join("\n")
        result 500, e.message
      end
    end

    def modify_indentifier(order_number)
      return "#{order_number}_1" if order_number.partition('_').last.empty?
      order_number_prefix = order_number.partition('_').last.to_i + 1
      "#{order_number}_#{order_number_prefix}"
    end

    def demodify_identyfier(modified_number)
      modified_number.partition('_').first
    end
  end
end
