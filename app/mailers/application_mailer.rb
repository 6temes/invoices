class ApplicationMailer < ActionMailer::Base
  default from: "daniel@6temes.cat"
  helper MailerHelper
  layout "mailer"
end
