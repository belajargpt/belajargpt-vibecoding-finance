class TransactionsController < ApplicationController
  before_action :set_transaction, only: [ :edit, :update, :destroy ]

  def index
    @transactions = Current.user.transactions.recent_first.limit(500)
  end

  def edit
    # Rendered inside a Turbo Frame targeting dom_id(@transaction). Full inline
    # form arrives in U5.
  end

  def update
    if @transaction.update(transaction_params)
      redirect_to transactions_path
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @transaction.destroy
    redirect_to transactions_path
  end

  private
    def set_transaction
      @transaction = Current.user.transactions.find(params[:id])
    end

    def transaction_params
      params.require(:transaction).permit(:amount_cents, :direction, :category, :occurred_on, :description)
    end
end
