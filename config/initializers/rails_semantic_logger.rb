# rails_semantic_logger logs the unpermitted-params context with its :request,
# and encoding that request as JSON recurses through the route AST until the
# stack overflows. Rails' own subscriber drops :request too; remove this once
# rails_semantic_logger does.
module UnpermittedParametersWithoutRequest
  def unpermitted_parameters(event)
    return super unless event.payload[:context]

    event = event.dup
    event.payload = event.payload.merge(context: event.payload[:context].except(:request))
    super
  end
end

RailsSemanticLogger::ActionController::LogSubscriber.prepend UnpermittedParametersWithoutRequest
