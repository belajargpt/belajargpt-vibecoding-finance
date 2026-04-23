require "ruby_llm/schema"

class TransactionParser
  Result = Data.define(:ok, :is_transaction, :entries, :reply_text, :error) do
    def ok? = ok
    def is_transaction? = is_transaction
  end

  # JSON schema the Parser Agent is constrained to return.
  class ParseSchema < RubyLLM::Schema
    description "Parsed Indonesian finance chat message"

    boolean :is_transaction, description: "true when the message logs at least one expense or income"
    array :entries, description: "One Ledger entry per item the user mentioned. Empty when is_transaction=false" do
      object do
        integer :amount_cents, description: "Amount in whole rupiah, always positive"
        string :direction, enum: %w[expense income]
        string :category, description: "Must match one of the allowed categories for the given direction"
        string :occurred_on, description: "ISO date (YYYY-MM-DD) resolved in Asia/Jakarta"
        string :description, description: "Short description of the item (e.g., 'batagor', 'bensin')"
      end
    end
    string :reply_text, description: "Non-empty when is_transaction=false. Reply shown in chat (Bahasa Indonesia)."
  end

  def initialize(chat_message)
    @chat_message = chat_message
  end

  # Jumlah pesan terakhir yang di-include sebagai context supaya Parser Agent
  # bisa menghubungkan follow-up ("3rb") ke pesan sebelumnya ("abis beli batagor").
  HISTORY_WINDOW = 4

  def parse
    response = RubyLLM.chat
      .with_instructions(system_prompt)
      .with_schema(ParseSchema)
      .ask(user_turn)

    build_result(response.content)
  rescue RubyLLM::Error, Timeout::Error, Faraday::Error => e
    Rails.logger.warn("[TransactionParser] #{e.class}: #{e.message}")
    Result.new(ok: false, is_transaction: false, entries: [], reply_text: nil, error: e.class.name)
  end

  private
    # Wrap current message with recent history so Claude can resolve follow-ups.
    # History is rendered inside the user turn (bukan system prompt) supaya
    # Claude perlakukan sebagai transkrip percakapan, bukan instruksi tetap.
    def user_turn
      history = recent_history
      return @chat_message.content if history.blank?

      lines = [ "KONTEKS PERCAKAPAN SEBELUMNYA (paling lama ke paling baru):" ]
      history.each do |prev|
        lines << %(- User: "#{prev.content}")
        next if prev.reply_text.blank?
        tag = case prev.parser_status
              when "logged"          then " (sudah kecatat: #{prev.transactions.count} transaksi)"
              when "not_transaction" then " (belum kecatat — mungkin nunggu jawaban user)"
              when "failed"          then " (gagal parse)"
              else ""
              end
        lines << %(  Kamu: "#{prev.reply_text}"#{tag})
      end
      lines << ""
      lines << "PESAN SEKARANG DARI USER (parse ini; pakai konteks di atas kalau pesan ini follow-up):"
      lines << @chat_message.content
      lines.join("\n")
    end

    def recent_history
      @chat_message.user.chat_messages
        .where.not(id: @chat_message.id)
        .order(created_at: :desc)
        .limit(HISTORY_WINDOW)
        .reverse
    end

    # Kata-kata yang nunjukin AI lagi ngonfirmasi transaksi. Kalau muncul di
    # reply_text sementara is_transaction=false, AI-nya bohong ke user.
    CONFIRMATION_WORDS = /\b(kecatat|kecatet|tercatat|dicatat|udah\s+masuk|masuk\s+(ledger|makanan|transport|belanja|hiburan|tagihan|kesehatan|lainnya|gaji|income)|saved|logged|done)\b/i

    def build_result(parsed)
      entries = Array(parsed["entries"]).map(&:symbolize_keys)
      raw_reply = parsed["reply_text"].to_s

      # Guard: is_transaction=true with empty entries is treated as non-transaction
      # so the UI path in F4 handles it cleanly (no row, polite reply).
      if parsed["is_transaction"] && entries.any?
        Result.new(
          ok: true,
          is_transaction: true,
          entries: entries,
          reply_text: raw_reply.presence,
          error: nil
        )
      else
        # Safety net: AI kadang bilang "udah kecatat!" tapi set is_transaction=false.
        # Ganti reply_text supaya user nggak mikir transaksi berhasil padahal belum.
        safe_reply = if raw_reply.match?(CONFIRMATION_WORDS)
          Rails.logger.warn("[TransactionParser] inconsistent output for ##{@chat_message.id}: " \
            "is_transaction=false but reply mentions confirmation: #{raw_reply.inspect}")
          "Hmm, aku kurang yakin. Coba tulis lebih detail ya — misal 'beli kopi 25rb'."
        else
          raw_reply.presence || "Gak ada transaksi yang kecatat dari pesan itu."
        end

        Result.new(
          ok: true,
          is_transaction: false,
          entries: [],
          reply_text: safe_reply,
          error: nil
        )
      end
    end

    def system_prompt
      now = Time.current
      <<~PROMPT
        Kamu adalah Parser Agent untuk aplikasi catatan keuangan pribadi berbahasa Indonesia.
        Tugasmu mengubah pesan chat pengguna jadi entri ledger terstruktur.

        Waktu sekarang (Asia/Jakarta): #{now.strftime('%Y-%m-%d %H:%M')} (#{now.strftime('%A')})

        ATURAN JUMLAH (parse apa adanya dari pesan, tanpa regex eksternal):
        - "5rb" = 5000, "5k" = 5000, "500rb" = 500000
        - "1jt" = 1000000, "1,5jt" = 1500000, "2.5jt" = 2500000
        - Angka biasa ("5000", "25000") juga valid
        - Jika pengguna menulis "Rp" di depan, abaikan "Rp" dan parse angkanya

        ATURAN TANGGAL (selalu Asia/Jakarta):
        - "kemarin" = tanggal kemarin (#{(now - 1.day).to_date})
        - "tadi pagi" / "tadi" / "barusan" = hari ini (#{now.to_date})
        - "minggu lalu" = 7 hari yang lalu (#{(now - 7.days).to_date})
        - Tanggal eksplisit "22 April" = tanggal itu di tahun #{now.year}
        - Kalau tidak disebutkan, pakai tanggal hari ini (#{now.to_date})

        ATURAN MULTI-ITEM:
        - Satu pesan bisa berisi beberapa item. Pisah jadi beberapa entri.
          Contoh: "beli nasi 25rb sama es teh 5rb" = 2 entri (25000 + 5000).
        - Kuantitas: "beli 2 nasi @25rb" = 2 entri identik @25000, BUKAN 1 entri 50000.
        - Satu pesan boleh campur expense + income (contoh:
          "dapet transfer 500rb trus beli baju 200rb" = 1 income + 1 expense).

        ATURAN DIRECTION:
        - expense: pengeluaran (beli, bayar, abis, jajan, langganan)
        - income: pemasukan (dapet, gajian, transfer masuk, bonus, hadiah)

        KATEGORI (WAJIB pakai persis salah satu dari list, cocok dengan direction):
        expense:
        - Makanan & Minuman (makanan, jajan, kopi, batagor, nasi, es teh, dll)
        - Transport (bensin, gojek, grab, parkir, tol, ojek)
        - Belanja (baju, barang, shopping, keperluan)
        - Hiburan (nonton, game, streaming, rekreasi)
        - Tagihan (listrik, air, internet, langganan, pulsa)
        - Kesehatan (obat, dokter, apotek, vitamin)
        - Lainnya (kalau benar-benar tidak pas di atas)

        income:
        - Gaji (gajian bulanan, upah kerja)
        - Lainnya (Income) (bonus, hadiah, transfer dari teman/keluarga, jual barang)

        ATURAN NON-TRANSAKSI:
        - Kalau pesannya sapaan / obrolan / perintah app ("halo", "oke", "liat ledger"),
          set is_transaction=false dengan reply_text menjelaskan singkat tidak ada yang dicatat.
        - Kalau pesannya JELAS transaksi tapi TIDAK ADA nominal ("abis beli batagor", "beli bensin")
          DAN konteks sebelumnya juga nggak kasih nominalnya,
          set is_transaction=false dengan reply_text berisi pertanyaan singkat
          minta nominalnya, misal: "Berapa harganya?" atau "Harganya berapa ya?".

        ATURAN FOLLOW-UP (PENTING — sering salah):
        - Kalau konteks sebelumnya kamu nanya harga / direction / detail ke user,
          dan pesan sekarang ngasih info yang kurang (contoh: "3rb", "expense", "kopi"),
          GABUNGIN konteks + pesan sekarang jadi entri lengkap:
            Contoh:
              Sebelumnya user: "abis beli batagor"
              Sebelumnya kamu: "Berapa harganya?"
              Sekarang user: "3rb"
              -> is_transaction=TRUE, entries=[{3000, expense, "Makanan & Minuman", today, "batagor"}]
        - KONSISTENSI MUTLAK: kalau reply_text kamu mengandung kata "kecatat",
          "masuk", "dicatat", "saved", "done" atau bentuk konfirmasi LAINNYA,
          is_transaction WAJIB true dan entries WAJIB diisi. JANGAN PERNAH bilang
          "udah kecatat" sementara is_transaction=false — itu kebohongan ke user.
        - Kalau kamu nggak yakin (info masih kurang), reply_text-nya TANYA lagi,
          jangan bilang "udah kecatat".

        REPLY_TEXT WAJIB DIISI SETIAP KALI, termasuk saat is_transaction=true:
        - Nada santai, kayak temen yang bantuin catet keuangan. Bahasa Indonesia casual.
        - 1 kalimat pendek, max ~80 karakter. Jangan ulang angkanya — angka udah ditampilkan
          di UI di bawah reply. Fokus ke acknowledgment + sedikit rasa personal.
        - VARIASIKAN kata pembuka — jangan selalu mulai dengan "Noted". Ganti-ganti pakai:
          "Oke", "Sip", "Siap", "Mantap", "Udah kecatat", "Kecatat", "Done", "Nih",
          "Cuss", "Gas", dll — pilih yang pas sama tone pesannya.
        - Contoh saat expense:
          * "beli kopi 25rb" -> "Sip, kopi udah kecatat!" / "Oke, kopinya masuk Makanan ✓"
            / "Cuss, kopi 25rb udah tercatat"
          * "gojek ke kantor 15rb" -> "Siap, gojeknya dicatat di Transport"
          * "beli baju 200rb" -> "Noted, belanjanya masuk ya"
        - Contoh saat income:
          * "gajian 10jt masuk" -> "Mantap! Gajian udah masuk 🎉"
            / "Alhamdulillah ya, gajinya kecatat"
          * "dapet bonus 500rb" -> "Wih mantap, bonusnya kecatat!"
        - Contoh saat multi-item:
          * "beli nasi 25rb sama es teh 5rb" -> "Oke, 2 item udah masuk Makanan"
          * "dapet 500rb trus beli baju 200rb" -> "Sip, dua-duanya udah kecatat"
        - Hindari kata "sukses" / "berhasil" yang formal — ini chat casual, bukan sistem enterprise.

        OUTPUT:
        - Selalu balas sesuai schema JSON.
        - reply_text WAJIB diisi baik saat is_transaction=true (acknowledgment kasual)
          maupun is_transaction=false (penjelasan/pertanyaan).
        - entries boleh array kosong kalau is_transaction=false.
      PROMPT
    end
end
