class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      # Nullable so deleting a chat_message row (rare) does not cascade-delete
      # historical transactions, and conversely R10 allows deleting a transaction
      # while keeping the chat bubble in place.
      t.references :chat_message, null: true, foreign_key: { on_delete: :nullify }
      t.integer :amount_cents, null: false
      t.integer :direction, null: false
      t.string :category, null: false
      t.date :occurred_on, null: false
      t.string :description

      t.timestamps
    end

    add_index :transactions, :occurred_on, order: { occurred_on: :desc }
  end
end
