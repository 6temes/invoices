module InvoicesHelper
  # Line item types are stored as denormalized English strings (e.g. "Service").
  # Localize them for customer-facing display, falling back to the stored value
  # for manually-entered types that have no translation.
  def item_type_label(item_type)
    t "invoice.item_types.#{item_type.parameterize(separator: '_')}", default: item_type
  end
end
