module ApplicationHelper
  # Canonical Indonesian Rupiah formatting used everywhere in the app.
  # R2: "IDR amounts render via number_to_currency ... e.g., `Rp 5.000`".
  def rupiah(amount_cents)
    number_to_currency(amount_cents, unit: "Rp ", separator: ",", delimiter: ".", precision: 0)
  end
end
