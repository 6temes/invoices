# A delayed payment Stripe is still waiting on. Only a bank transfer carries figures:
# what has arrived so far, what is still to send, and where to send it.
Invoice::PendingPayment = Data.define(:amount_received, :amount_remaining, :instructions_url, :bank_details) do
  def self.from(intent)
    instructions = intent["next_action"]&.[]("display_bank_transfer_instructions")
    return new unless instructions

    zengin = instructions.financial_addresses.find { it.type == "zengin" }.zengin
    new amount_received: intent.amount - instructions.amount_remaining,
      amount_remaining: instructions.amount_remaining,
      instructions_url: instructions.hosted_instructions_url,
      bank_details: zengin.to_hash.slice(:bank_name, :branch_name, :account_type, :account_number, :account_holder_name)
  end

  def initialize(amount_received: nil, amount_remaining: nil, instructions_url: nil, bank_details: nil)
    super
  end

  def bank_transfer?
    !amount_remaining.nil?
  end
end
