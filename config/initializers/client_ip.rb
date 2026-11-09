# Both are needed: without the priority a visitor's Forwarded header chooses the client IP, and
# with the check on a Client-IP header missing from X-Forwarded-For raises IpSpoofAttackError (a 500).
Rack::Request.forwarded_priority = [ :x_forwarded ]
Rails.application.config.action_dispatch.ip_spoofing_check = false
