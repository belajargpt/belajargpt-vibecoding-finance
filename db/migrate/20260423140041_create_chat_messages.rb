class CreateChatMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 0
      t.text :content, null: false
      t.integer :parser_status, null: false, default: 0
      t.text :reply_text

      t.timestamps
    end

    add_index :chat_messages, [ :user_id, :created_at ]
  end
end
