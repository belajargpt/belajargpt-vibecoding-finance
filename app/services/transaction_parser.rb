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

  def parse
    response = RubyLLM.chat
      .with_instructions(system_prompt)
      .with_schema(ParseSchema)
      .ask(@chat_message.content)

    build_result(response.content)
  rescue RubyLLM::Error, Timeout::Error, Faraday::Error => e
    Rails.logger.warn("[TransactionParser] #{e.class}: #{e.message}")
    Result.new(ok: false, is_transaction: false, entries: [], reply_text: nil, error: e.class.name)
  end

  private
    def build_result(parsed)
      entries = Array(parsed["entries"]).map(&:symbolize_keys)

      # Guard: is_transaction=true with empty entries is treated as non-transaction
      # so the UI path in F4 handles it cleanly (no row, polite reply).
      if parsed["is_transaction"] && entries.any?
        Result.new(
          ok: true,
          is_transaction: true,
          entries: entries,
          reply_text: parsed["reply_text"].presence,
          error: nil
        )
      else
        Result.new(
          ok: true,
          is_transaction: false,
          entries: [],
          reply_text: parsed["reply_text"].presence || "Gak ada transaksi yang kecatat dari pesan itu.",
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
        - Kalau pesannya JELAS transaksi tapi TIDAK ADA nominal ("abis beli batagor", "beli bensin"),
          set is_transaction=false dengan reply_text berisi pertanyaan singkat
          minta nominalnya, misal: "Berapa harganya?" atau "Harganya berapa ya?".

        OUTPUT:
        - Selalu balas sesuai schema JSON. entries boleh array kosong kalau is_transaction=false.
        - reply_text wajib diisi saat is_transaction=false.
      PROMPT
    end
end
